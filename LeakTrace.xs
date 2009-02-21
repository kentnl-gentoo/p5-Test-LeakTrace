#define PERL_NO_GET_CONTEXT /* I want efficiency. */
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#include "ppport.h"

#define MY_CXT_KEY "Test::LeakTrace::_guts" XS_VERSION
typedef struct{
	bool enabled;
	bool need_stateinfo;

	Perl_ppaddr_t nextstate;
	Perl_ppaddr_t dbstate;

	PTR_TBL_t* usedsv_reg;
	PTR_TBL_t* newsv_reg;

} my_cxt_t;
START_MY_CXT;

struct stateinfo;
struct stateinfo{
	SV* sv;

	const char* file;
	I32         filelen;
	I32         line;

	struct stateinfo* next;
};

#define ptr_table_free_val(tbl) my_ptr_table_free_val(aTHX_ tbl)
static void
my_ptr_table_free_val(pTHX_ PTR_TBL_t * const tbl){
    if (tbl->tbl_items) {
	register PTR_TBL_ENT_t * const * const array = tbl->tbl_ary;
	UV riter = tbl->tbl_max;

	do {
	    PTR_TBL_ENT_t *entry = array[riter];

	    while (entry) {
		Safefree( ((struct stateinfo*)entry->newval)->file );
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
#define START_VISIT STMT_START{                                        \
	dVAR; SV* sva;                                                 \
	for(sva = PL_sv_arenaroot; sva; sva = (SV*)SvANY(sva)){        \
		register const SV * const svend = &sva[SvREFCNT(sva)]; \
		register SV* sv;                                       \
		for(sv = sva + 1; sv < svend; ++sv){                   \
			if (SvTYPE(sv) != SVTYPEMASK && SvREFCNT(sv))  \

#define END_VISIT                  \
		} /* end for(1) */ \
	} /* end for(2) */         \
	} STMT_END


static void
mark_all(pTHX_ pMY_CXT_ bool const need_stateinfo){
	const char* const file    = CopFILE(PL_curcop);
	I32 const         filelen = strlen(file);
	I32 const         line    = (I32)CopLINE(PL_curcop);

	START_VISIT {

		/* mark as "new" with statement info */

		if(!ptr_table_fetch(MY_CXT.usedsv_reg, sv) && !ptr_table_fetch(MY_CXT.newsv_reg, sv)){
			struct stateinfo* si;
			Newx(si, 1, struct stateinfo);

			si->sv      = sv;

			if(need_stateinfo){
				si->file    = savepv(file);
				si->filelen = filelen;
				si->line    = line;
			}
			else{
				si->file    = NULL;
				si->filelen = 0;
				si->line    = 0;
			}
			si->next    = NULL;

			ptr_table_store(MY_CXT.newsv_reg, sv, si);
		}
	} END_VISIT;
}


static OP*
leaktrace_nextstate(pTHX){
	dMY_CXT;

	if(MY_CXT.enabled)
		mark_all(aTHX_ aMY_CXT_ TRUE);

	return CALL_FPTR(MY_CXT.nextstate)(aTHX);
}
static OP*
leaktrace_dbstate(pTHX){
	dMY_CXT;

	if(MY_CXT.enabled)
		mark_all(aTHX_ aMY_CXT_ TRUE);

	return CALL_FPTR(MY_CXT.dbstate)(aTHX);
}

static void
callback_each_leaked(pTHX_ struct stateinfo* leaked, SV* const callback){
	GV* const gv = PL_defgv;
	SV* filesv;
	SV* linesv;

	ENTER;
	SAVETMPS;
	SAVESPTR(GvSV(gv));

	filesv = sv_newmortal();
	linesv = sv_newmortal();

	while(leaked){
		SV* const sv = newRV_inc(leaked->sv);
		dSP;
		PUSHMARK(SP);

		GvSV(gv) = sv;

		if(leaked->file){
			sv_setpvn(filesv, leaked->file, leaked->filelen);
			sv_setiv(linesv, leaked->line);

			EXTEND(SP, 3);
			PUSHs(sv);
			PUSHs(filesv);
			PUSHs(linesv);
		}
		else{
			XPUSHs(sv);
		}
		PUTBACK;

		call_sv(callback, G_VOID | G_EVAL | G_DISCARD);
		if(SvTRUE(ERRSV)){
			Perl_warn(aTHX_ "%"SVf, ERRSV);
		}

		SvREFCNT_dec(sv);
		leaked = leaked->next;
	}

	FREETMPS;
	LEAVE;
}
static void
report_each_leaked(pTHX_ struct stateinfo* leaked, bool const verbose){
	while(leaked){
		if(leaked->file){
			PerlIO_printf(Perl_debug_log, "#leaked %s(0x%p) at %s line %d.\n",
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

static void
leaktrace_cxt_init(pTHX_ pMY_CXT){

	MY_CXT.nextstate        = PL_ppaddr[OP_NEXTSTATE];
	MY_CXT.dbstate          = PL_ppaddr[OP_DBSTATE];

	PL_ppaddr[OP_NEXTSTATE] = leaktrace_nextstate;
	PL_ppaddr[OP_DBSTATE]   = leaktrace_dbstate;
}

MODULE = Test::LeakTrace	PACKAGE = Test::LeakTrace

PROTOTYPES: DISABLE

BOOT:
{
	MY_CXT_INIT;
	leaktrace_cxt_init(aTHX_ aMY_CXT);
}

void
CLONE(...)
CODE:
	MY_CXT_CLONE;
	MY_CXT.enabled    = FALSE;
	MY_CXT.usedsv_reg = NULL;
	MY_CXT.newsv_reg  = NULL;
	PERL_UNUSED_VAR(items);

void
_start(bool need_stateinfo)
PREINIT:
	dMY_CXT;
CODE:
	if(MY_CXT.usedsv_reg){
		Perl_croak(aTHX_ "Cannot start LeakTrace inside its scope");
	}

	MY_CXT.need_stateinfo   = need_stateinfo;
	MY_CXT.usedsv_reg       = ptr_table_new();
	MY_CXT.newsv_reg        = ptr_table_new();

	START_VISIT{
		/* mark as "used" */
		ptr_table_store(MY_CXT.usedsv_reg, sv, sv);
	} END_VISIT;
	if(need_stateinfo)
		MY_CXT.enabled = TRUE;

void
_finish(SV* mode = NULL)
PREINIT:
	I32 const gimme = GIMME_V;
	dMY_CXT;
	struct stateinfo* leaked = NULL;
	IV count = 0;
	bool verbose = FALSE;
	SV* callback = NULL;
PPCODE:
	if(!MY_CXT.usedsv_reg){
		Perl_warn(aTHX_ "LeakTrace not started");
		XSRETURN_EMPTY;
	}
	assert(MY_CXT.newsv_reg);

	MY_CXT.enabled = FALSE;

	if(mode){
		if(gimme != G_VOID){
			Perl_croak(aTHX_ "'mode' makes no sense in non-void context");
		}

		if(SvROK(mode) && SvTYPE(SvRV(mode)) == SVt_PVCV){
			callback = mode;
		}
		else{
			verbose = SvTRUE(mode);
		}
	}

	mark_all(aTHX_ aMY_CXT_ MY_CXT.need_stateinfo);

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
			SV* sv = newRV_inc(leaked->sv);

			if(leaked->file){
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
	else{ /* gimme == G_VOID */
		if(callback){
			callback_each_leaked(aTHX_ leaked, callback);
		}
		else{
			report_each_leaked(aTHX_ leaked, verbose);
		}
	}

	ptr_table_free_val(MY_CXT.newsv_reg);
	ptr_table_free(MY_CXT.newsv_reg);
	MY_CXT.newsv_reg = NULL;

