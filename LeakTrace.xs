#define PERL_NO_GET_CONTEXT /* I want efficiency. */
#include <EXTERN.h>
#include <perl.h>
#define NO_XSLOCKS /* use exception handling macros */
#include <XSUB.h>

#include "ppport.h"

#include "ptr_table.h"

#ifndef SvIS_FREED
#define SvIS_FREED(sv) (SvFLAGS(sv) == SVTYPEMASK)
#endif

#define FILENAME_SIZE 50

#define MY_CXT_KEY "Test::LeakTrace::_guts" XS_VERSION
typedef struct{
	bool enabled;
	bool need_stateinfo;

	char        file[FILENAME_SIZE];
	I32         filelen;
	I32         line;

	runops_proc_t runops;

	PTR_TBL_t* usedsv_reg;
	PTR_TBL_t* newsv_reg;

} my_cxt_t;
START_MY_CXT;

struct stateinfo;
struct stateinfo{
	SV* sv;

	char file[FILENAME_SIZE];
	I32  filelen;
	I32  line;

	struct stateinfo* next;
};

#define ptr_table_free_val(tbl) my_ptr_table_free_val(aTHX_ tbl)
static void
my_ptr_table_free_val(pTHX_ PTR_TBL_t * const tbl){
	assert(tbl);
	if (tbl->tbl_items) {
		PTR_TBL_ENT_t * const * const array = tbl->tbl_ary;
		UV riter = tbl->tbl_max;

		do {
			register PTR_TBL_ENT_t *entry = array[riter];

			while (entry) {
				if(entry->newval){
					Safefree(entry->newval);
					entry->newval = NULL;
				}

				entry = entry->next;
			}
		} while (riter--);
	}
}

/* START_VISIT and END_VISIT macros are originated from S_visit() in sv.c.
   They are used to scan the sv arena.
*/
#define START_VISIT STMT_START{                                  \
	SV* sva;                                                 \
	for(sva = PL_sv_arenaroot; sva; sva = (SV*)SvANY(sva)){  \
		const SV * const svend = &sva[SvREFCNT(sva)];    \
		register SV* sv;                                 \
		for(sv = sva + 1; sv < svend; ++sv){             \
			if (!SvIS_FREED(sv))

#define END_VISIT                  \
		} /* end for(1) */ \
	} /* end for(2) */         \
	} STMT_END


static I32
my_min(I32 const x, I32 const y){
	return x < y ? x : y;
}

static void
set_stateinfo(pTHX_ pMY_CXT_ const char* const file, I32 const line){
	I32 filelen;
	assert(file);

	filelen = strlen(file);
	MY_CXT.filelen = my_min(filelen, sizeof(MY_CXT.file)-1);

	if(filelen == MY_CXT.filelen){
		Copy(file, MY_CXT.file, MY_CXT.filelen, char);
	}
	else{ /* truncated */
		Copy(file + (filelen - MY_CXT.filelen), MY_CXT.file, MY_CXT.filelen, char);
		Copy("...", MY_CXT.file, 3, char);
	}
	MY_CXT.file[MY_CXT.filelen] = '\0';

	MY_CXT.line = line;
}

static void
mark_all(pTHX_ pMY_CXT){
	assert(MY_CXT.usedsv_reg);
	assert(MY_CXT.newsv_reg);

	/* unmark freed SVs */
	if (MY_CXT.newsv_reg->tbl_items) {
		register PTR_TBL_ENT_t * const * const array = MY_CXT.newsv_reg->tbl_ary;
		UV riter = MY_CXT.newsv_reg->tbl_max;

		do {
			PTR_TBL_ENT_t *entry = array[riter];

			while (entry) {
				struct stateinfo* const si = (struct stateinfo*)entry->newval;

				if(si && SvIS_FREED(si->sv)){
					Safefree(si);
					entry->newval = NULL;
				}

				entry = entry->next;
			}
		} while (riter--);
	}

	/* mark SVs as "new" with statement info */
	START_VISIT {
		if(!ptr_table_fetch(MY_CXT.usedsv_reg, sv) && !ptr_table_fetch(MY_CXT.newsv_reg, sv)){
			struct stateinfo* si;

			Newxz(si, 1, struct stateinfo);

			ptr_table_store(MY_CXT.newsv_reg, sv, si);
			si->sv   = sv;

			if(MY_CXT.need_stateinfo){
				Copy(MY_CXT.file, si->file, MY_CXT.filelen+1, char);
				si->filelen = MY_CXT.filelen;
				si->line    = MY_CXT.line;
			}
		}
	} END_VISIT;
}

static int
leaktrace_runops(pTHX){
	dVAR;
	dMY_CXT;

	set_stateinfo(aTHX_ aMY_CXT_ CopFILE(PL_curcop), CopLINE(PL_curcop));

	while((PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX))) {
		PERL_ASYNC_CHECK();

		if(!MY_CXT.need_stateinfo) continue;

		if(PL_op->op_type == OP_NEXTSTATE || PL_op->op_type == OP_DBSTATE){
			mark_all(aTHX_ aMY_CXT);

			set_stateinfo(aTHX_ aMY_CXT_ CopFILE(PL_curcop), CopLINE(PL_curcop));
		}
	}

	if(MY_CXT.enabled){
		mark_all(aTHX_ aMY_CXT);
	}

	TAINT_NOT;
	return 0;
}

static void
callback_each_leaked(pTHX_ struct stateinfo* leaked, SV* const callback){
	while(leaked){
		dSP;
		I32 n;

		if(SvIS_FREED(leaked->sv)){
			/* NOTE: it is possible when the callback releases some SVs. */
			leaked = leaked->next;
			continue;
		}

		ENTER;
		SAVETMPS;

		PUSHMARK(SP);

		mXPUSHs(newRV_inc(leaked->sv));

		if(leaked->filelen){
			EXTEND(SP, 2);
			mPUSHp(leaked->file, leaked->filelen);
			mPUSHi(leaked->line);
		}

		PUTBACK;

		n = call_sv(callback, G_VOID);

		SPAGAIN;
		while(n--) POPs;
		PUTBACK;

		FREETMPS;
		LEAVE;

		leaked = leaked->next;
	}
}
static void
report_each_leaked(pTHX_ struct stateinfo* leaked, bool const verbose){
	while(leaked){
		assert(!SvIS_FREED(leaked->sv));

		if(leaked->filelen){
			PerlIO_printf(Perl_debug_log, "#leaked %s(0x%p) from %s line %d.\n",
				sv_reftype(leaked->sv, FALSE),
				leaked->sv,
				leaked->file, (int)leaked->line);
		}

		if(verbose){
			sv_dump(leaked->sv);
		}
		leaked = leaked->next;
	}
}


MODULE = Test::LeakTrace	PACKAGE = Test::LeakTrace

PROTOTYPES: DISABLE

BOOT:
{
	MY_CXT_INIT;
	MY_CXT.usedsv_reg     = NULL;
	MY_CXT.newsv_reg      = NULL;
	MY_CXT.enabled        = FALSE;
	MY_CXT.need_stateinfo = FALSE;
	MY_CXT.runops         = PL_runops;
	PL_runops             = leaktrace_runops;
}

void
CLONE(...)
CODE:
	MY_CXT_CLONE;
	MY_CXT.usedsv_reg     = NULL;
	MY_CXT.newsv_reg      = NULL;
	MY_CXT.enabled        = FALSE;
	MY_CXT.need_stateinfo = FALSE;
	PERL_UNUSED_VAR(items);

void
_start(bool need_stateinfo)
PREINIT:
	dMY_CXT;
CODE:
	if(MY_CXT.enabled){
		Perl_croak(aTHX_ "Cannot start LeakTrace inside its scope");
	}
	assert(MY_CXT.usedsv_reg == NULL);
	assert(MY_CXT.newsv_reg  == NULL);

	MY_CXT.enabled          = TRUE;
	MY_CXT.need_stateinfo   = need_stateinfo;
	MY_CXT.usedsv_reg       = ptr_table_new();
	MY_CXT.newsv_reg        = ptr_table_new();

	START_VISIT{
		/* mark as "used" */
		ptr_table_store(MY_CXT.usedsv_reg, sv, sv);
	} END_VISIT;

void
_finish(SV* mode = &PL_sv_undef)
PREINIT:
	I32 gimme = GIMME_V;
	dMY_CXT;
	IV count = 0;
	struct stateinfo* volatile leaked = NULL; /* volatile to pass -Wuninitialized (longjmp) */
	SV* volatile callback = NULL;             /* volatile to pass -Wuninitialized (longjmp) */
	bool verbose = FALSE;
PPCODE:
	if(!MY_CXT.enabled){
		Perl_warn(aTHX_ "LeakTrace not started");
		XSRETURN_EMPTY;
	}

	if(SvOK(mode)){
		gimme = G_VOID; /* reporting mode */

		if(SvROK(mode) && SvTYPE(SvRV(mode)) == SVt_PVCV){
			callback = mode;
		}
		else{
			verbose = SvTRUE(mode);
		}
	}
	assert(MY_CXT.usedsv_reg);
	assert(MY_CXT.newsv_reg);

	mark_all(aTHX_ aMY_CXT);

	MY_CXT.enabled        = FALSE;
	MY_CXT.need_stateinfo = FALSE;

	START_VISIT{
		struct stateinfo* const si = (struct stateinfo*)ptr_table_fetch(MY_CXT.newsv_reg, sv);

		if(si){
			count++;
			si->next = leaked; /* make a link */
			leaked = si;
		}
	} END_VISIT;

	ptr_table_free(MY_CXT.usedsv_reg);
	MY_CXT.usedsv_reg = NULL;

	if(gimme == G_SCALAR){
		mXPUSHi(count);
	}
	else if(gimme == G_ARRAY){
		EXTEND(SP, count);
		while(leaked){
			SV* sv;

			sv = newRV_inc(leaked->sv);

			if(leaked->filelen){
				AV* const av = newAV();

				av_push(av, sv);
				av_push(av, newSVpvn(leaked->file, leaked->filelen));
				av_push(av, newSVuv(leaked->line));
				sv = newRV_noinc((SV*)av);
			}
			mPUSHs(sv);

			leaked = leaked->next;
		}
	}
	else{ /* reporting mode */
		if(callback){
			dXCPT;
			XCPT_TRY_START {
				callback_each_leaked(aTHX_ leaked, callback);
			} XCPT_TRY_END

			XCPT_CATCH {
				ptr_table_free_val(MY_CXT.newsv_reg);
				ptr_table_free(MY_CXT.newsv_reg);
				MY_CXT.newsv_reg = NULL;

				XCPT_RETHROW;
			}
		}
		else{
			report_each_leaked(aTHX_ leaked, verbose);
		}
	}

	ptr_table_free_val(MY_CXT.newsv_reg);
	ptr_table_free(MY_CXT.newsv_reg);
	MY_CXT.newsv_reg = NULL;

