#define PERL_NO_GET_CONTEXT /* I want efficiency. */
#include <EXTERN.h>
#include <perl.h>
#define NO_XSLOCKS /* use exception handling macros */
#include <XSUB.h>

#define NEED_newSVpvn_flags /* newSVpvs_flags depends on */
#include "ppport.h"

#include "ptr_table.h"

#ifndef SvIS_FREED
#define SvIS_FREED(sv) (SvFLAGS(sv) == SVTYPEMASK)
#endif

#define PteKey(pte) ((SV*)pte->oldval)
#define PteVal(pte) ((struct stateinfo*)pte->newval)

#define REPORT_DISABLED     0x00
#define REPORT_ENABLED      0x01
#define REPORT_SV_DUMP      0x02
#define REPORT_SOURCE_LINES 0x04
#define REPORT_SILENT       0x08

#define MY_CXT_KEY "Test::LeakTrace::_guts" XS_VERSION
typedef struct{
	bool enabled;
	bool need_stateinfo;

	char* file;
	int   filelen;
	int   line;

	PTR_TBL_t* usedsv_reg;
	PTR_TBL_t* newsv_reg;

} my_cxt_t;
START_MY_CXT;

struct stateinfo;
struct stateinfo{
	SV* sv;

	char* file;
	int   filelen;
	int   line;

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
				Safefree(PteVal(entry)->file);
				Safefree(entry->newval);
				entry->newval = NULL;

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


static void
set_stateinfo(pTHX_ pMY_CXT_ COP* const cop){
	const char* file;
	assert(cop);

	file = CopFILE(cop);
	assert(file);

	MY_CXT.filelen = strlen(file);
	Renew(MY_CXT.file, MY_CXT.filelen+1, char);
	Copy(file, MY_CXT.file, MY_CXT.filelen+1, char);

	MY_CXT.line = (int)CopLINE(cop);
}

static void
unmark_all(pTHX_ pMY_CXT){
	assert(MY_CXT.newsv_reg);

	if (MY_CXT.newsv_reg->tbl_items) {
		PTR_TBL_ENT_t * const * const array = MY_CXT.newsv_reg->tbl_ary;
		UV riter = MY_CXT.newsv_reg->tbl_max;

		do {
			register PTR_TBL_ENT_t *entry = array[riter];

			while (entry) {
				if(SvIS_FREED(PteKey(entry))){
					PteVal(entry)->sv = NULL; /* unmark */
				}

				entry = entry->next;
			}
		} while (riter--);
	}
}

static void
mark_all(pTHX_ pMY_CXT){
	assert(MY_CXT.usedsv_reg);
	assert(MY_CXT.newsv_reg);

	unmark_all(aTHX_ aMY_CXT);

	/* mark SVs as "new" with statement info */
	START_VISIT {
		if(!ptr_table_fetch(MY_CXT.usedsv_reg, sv)){
			struct stateinfo* si = (struct stateinfo*)ptr_table_fetch(MY_CXT.newsv_reg, sv);

			if(si){
				if(si->sv){
					/* already marked */
					continue;
				}
				/* unmarked */
			}
			else{
				/* not marked */
				Newxz(si, 1, struct stateinfo);
				ptr_table_store(MY_CXT.newsv_reg, sv, si);
			}
			si->sv   = sv; /* mark */

			if(MY_CXT.need_stateinfo){
				Renew(si->file, MY_CXT.filelen+1, char);
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
	COP* last_cop = PL_curcop;

	while((PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX))) {
		PERL_ASYNC_CHECK();

		if(!MY_CXT.need_stateinfo) continue;

#if 0
		PerlIO_printf(Perl_debug_log, "#run [%s] %s %d\n",
			OP_NAME(PL_op),
			CopFILE(PL_curcop),
			(int)CopLINE(PL_curcop));
#endif

		if(last_cop != PL_curcop){
			mark_all(aTHX_ aMY_CXT);
			last_cop = PL_curcop;
			set_stateinfo(aTHX_ aMY_CXT_ last_cop);
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

		if(SvIS_FREED(leaked->sv)){ /* NOTE: it is possible when the callback releases some SVs. */
			leaked = leaked->next;
			continue;
		}

		ENTER;
		SAVETMPS;

		PUSHMARK(SP);

		EXTEND(SP, 3);
		mXPUSHs(newRV_inc(leaked->sv));

		mPUSHp(leaked->file, leaked->filelen);
		mPUSHi(leaked->line);

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
print_lines_around(pTHX_ PerlIO* const ofp, const char* const file, int const lineno){
	PerlIO* const ifp = PerlIO_open(file, "r");
	SV* const sv = DEFSV;
	int i = 0;
	if(ifp){
		while(sv_gets(sv, ifp, FALSE)){
			i++;

			if( i >= (lineno-1) ){
				PerlIO_printf(ofp, "%4d:%"SVf, i, sv);

				if( i >= (lineno+1) ){
					break;
				}
			}
		}
		PerlIO_close(ifp);
	}
}

static void
report_each_leaked(pTHX_ struct stateinfo* leaked, int const reporting_mode){
	PerlIO* const logfp = Perl_error_log;

	if(reporting_mode & REPORT_SILENT){
		return;
	}

	if(reporting_mode & REPORT_SOURCE_LINES){
		ENTER;
		SAVETMPS;

		 /*
		     local $/ = "\n"
		     local $_;
		  */
		SAVESPTR(PL_rs);
		SAVE_DEFSV;

		PL_rs = newSVpvs_flags("\n", SVs_TEMP);
		DEFSV = sv_newmortal();
	}

	while(leaked){
		assert(!SvIS_FREED(leaked->sv));

		if(leaked->filelen){
			PerlIO_printf(logfp, "leaked %s(0x%p) from %s line %d.\n",
				sv_reftype(leaked->sv, FALSE),
				leaked->sv,
				leaked->file, leaked->line);

			if(leaked->line && (reporting_mode & REPORT_SOURCE_LINES)){
				print_lines_around(aTHX_ logfp, leaked->file, leaked->line);
			}
		}

		if(reporting_mode & REPORT_SV_DUMP){
			do_sv_dump(
				0,     /* level */
				logfp,
				leaked->sv,
				0,     /* nest */
				4,     /* maxnest */
				FALSE, /* dumpops */
				0      /* pvlim */
			);
		}
		leaked = leaked->next;
	}

	if(reporting_mode & REPORT_SOURCE_LINES){
		FREETMPS;
		LEAVE;
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
	dMY_CXT;
	I32 const gimme    = GIMME_V;
	int reporting_mode = REPORT_DISABLED;
	IV count           = 0;
	/* volatile to pass -Wuninitialized (longjmp) */
	struct stateinfo* volatile leaked = NULL;
	SV* volatile callback             = NULL;
	SV* volatile invalid_mode         = NULL;
PPCODE:
	if(!MY_CXT.enabled){
		Perl_warn(aTHX_ "LeakTrace not started");
		XSRETURN_EMPTY;
	}

	if(SvOK(mode)){
		if(SvROK(mode) && SvTYPE(SvRV(mode)) == SVt_PVCV){
			reporting_mode = REPORT_ENABLED;
			callback = mode;
		}
		else{
			const char* const modepv = SvPV_nolen_const(mode);

			if(strEQ(modepv, "-simple")){
				reporting_mode = REPORT_ENABLED;
			}
			else if(strEQ(modepv, "-sv_dump")){
				reporting_mode = REPORT_SV_DUMP;
			}
			else if(strEQ(modepv, "-lines")){
				reporting_mode = REPORT_SOURCE_LINES;
			}
			else if(strEQ(modepv, "-verbose")){
				reporting_mode = REPORT_SV_DUMP | REPORT_SOURCE_LINES;
			}
			else if(strEQ(modepv, "-silent")){
				reporting_mode = REPORT_SILENT;
			}
			else{
				reporting_mode = REPORT_SILENT;
				invalid_mode   = mode;
			}
		}
	}
	assert(MY_CXT.usedsv_reg);
	assert(MY_CXT.newsv_reg);

	mark_all(aTHX_ aMY_CXT);

	MY_CXT.enabled        = FALSE;
	MY_CXT.need_stateinfo = FALSE;

	START_VISIT{
		struct stateinfo* const si = (struct stateinfo*)ptr_table_fetch(MY_CXT.newsv_reg, sv);

		if(si && si->sv){
			count++;
			si->next = leaked; /* make a link */
			leaked = si;
		}
	} END_VISIT;

	ptr_table_free(MY_CXT.usedsv_reg);
	MY_CXT.usedsv_reg = NULL;

	if(reporting_mode){
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
			report_each_leaked(aTHX_ leaked, reporting_mode);
		}
	}
	else if(gimme == G_SCALAR){
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
				av_push(av, newSViv(leaked->line));
				sv = newRV_noinc((SV*)av);
			}
			mPUSHs(sv);

			leaked = leaked->next;
		}
	}

	ptr_table_free_val(MY_CXT.newsv_reg);
	ptr_table_free(MY_CXT.newsv_reg);
	MY_CXT.newsv_reg = NULL;

	if(invalid_mode){
		Perl_croak(aTHX_ "Invalid reporting mode: %"SVf, invalid_mode);
	}

