/* Hej, Emacs, this is -*- C -*- mode!

   Copyright (c) 2018      GoodData Corporation
   Copyright (c) 2015-2017 Pali Rohár
   Copyright (c) 2004-2017 Patrick Galbraith
   Copyright (c) 2013-2017 Michiel Beijen
   Copyright (c) 2004-2007 Alexey Stroganov
   Copyright (c) 2003-2005 Rudolf Lippan
   Copyright (c) 1997-2003 Jochen Wiedmann

   You may distribute under the terms of either the GNU General Public
   License or the Artistic License, as specified in the Perl README file.

*/


#include "dbdimp.h"
#include "constants.h"

#include <errno.h>
#include <string.h>

#define ASYNC_CHECK_XS(h)\
  if(imp_dbh->async_query_in_flight) {\
      mariadb_dr_do_error(h, 2000, "Calling a synchronous function on an asynchronous handle", "HY000");\
      XSRETURN_UNDEF;\
  }


DBISTATE_DECLARE;


MODULE = DBD::MariaDB	PACKAGE = DBD::MariaDB

INCLUDE: MariaDB.xsi

MODULE = DBD::MariaDB	PACKAGE = DBD::MariaDB

double
constant(name, arg)
    char* name
    char* arg
  CODE:
    RETVAL = mariadb_constant(name, arg);
  OUTPUT:
    RETVAL


MODULE = DBD::MariaDB	PACKAGE = DBD::MariaDB::dr

void
_ListDBs(drh, host=NULL, port=NULL, user=NULL, password=NULL, enable_utf8=false)
    SV *        drh
    char *	host
    char *      port
    char *      user
    char *      password
    bool        enable_utf8
  PPCODE:
{
    MYSQL mysql;
    mysql.net.fd = -1;
    MYSQL* sock = mariadb_dr_connect(drh, &mysql, NULL, host, port, user, password,
				   NULL, NULL);
    if (sock != NULL)
    {
      MYSQL_ROW cur;
      MYSQL_RES* res;
      MYSQL_FIELD* field;

      if (enable_utf8)
        mysql_set_character_set(sock, "utf8");

      res = mysql_list_dbs(sock, NULL);
      if (!res)
      {
        mariadb_dr_do_error(drh, mysql_errno(sock), mysql_error(sock), mysql_sqlstate(sock));
      }
      else
      {
	field = mysql_fetch_field(res);
	EXTEND(sp, mysql_num_rows(res));
	while ((cur = mysql_fetch_row(res)))
        {
	  SV* sv = sv_2mortal(newSVpvn(cur[0], strlen(cur[0])));
#if MYSQL_VERSION_ID >= FIELD_CHARSETNR_VERSION
	  if (enable_utf8 && field && charsetnr_is_utf8(field->charsetnr))
#else
	  if (enable_utf8 && field && !(field->flags & BINARY_FLAG))
#endif
	    sv_utf8_decode(sv);
	  PUSHs(sv);
	}
	mysql_free_result(res);
      }
      mysql_close(sock);
    }
}


void
_admin_internal(drh,dbh,command,dbname=NULL,host=NULL,port=NULL,user=NULL,password=NULL)
  SV* drh
  SV* dbh
  char* command
  char* dbname
  char* host
  char* port
  char* user
  char* password
  PPCODE:
{
  MYSQL mysql;
  int retval;
  MYSQL* sock;
#if MYSQL_VERSION_ID >= 50709
  const char *shutdown = "SHUTDOWN";
#endif

  /*
   *  Connect to the database, if required.
 */
  if (SvOK(dbh)) {
    D_imp_dbh(dbh);
    sock = imp_dbh->pmysql;
  }
  else
  {
    mysql.net.fd = -1;
    sock = mariadb_dr_connect(drh, &mysql, NULL, host, port, user,  password, NULL, NULL);
    if (sock == NULL)
    {
      mariadb_dr_do_error(drh, mysql_errno(&mysql), mysql_error(&mysql),
               mysql_sqlstate(&mysql));
      XSRETURN_NO;
    }
  }

  if (strEQ(command, "shutdown"))
#if MYSQL_VERSION_ID < 40103
    retval = mysql_shutdown(sock);
#else
#if MYSQL_VERSION_ID < 50709
    retval = mysql_shutdown(sock, SHUTDOWN_DEFAULT);
#else
    retval = mysql_real_query(sock, shutdown, strlen(shutdown));
#endif
#endif
  else if (strEQ(command, "reload"))
    retval = mysql_reload(sock);
  else if (strEQ(command, "createdb"))
  {
#if MYSQL_VERSION_ID < 40000
    retval = mysql_create_db(sock, dbname);
#else
    char* buffer = malloc(strlen(dbname)+50);
    if (buffer == NULL)
    {
      mariadb_dr_do_error(drh, JW_ERR_MEM, "Out of memory" ,NULL);
      XSRETURN_NO;
    }
    else
    {
      strcpy(buffer, "CREATE DATABASE ");
      strcat(buffer, dbname);
      retval = mysql_real_query(sock, buffer, strlen(buffer));
      free(buffer);
    }
#endif
  }
  else if (strEQ(command, "dropdb"))
  {
#if MYSQL_VERSION_ID < 40000
    retval = mysql_drop_db(sock, dbname);
#else
    char* buffer = malloc(strlen(dbname)+50);
    if (buffer == NULL)
    {
      mariadb_dr_do_error(drh, JW_ERR_MEM, "Out of memory" ,NULL);
      XSRETURN_NO;
    }
    else
    {
      strcpy(buffer, "DROP DATABASE ");
      strcat(buffer, dbname);
      retval = mysql_real_query(sock, buffer, strlen(buffer));
      free(buffer);
    }
#endif
  }
  else
  {
    mariadb_dr_do_error(drh, JW_ERR_INVALID_ATTRIBUTE, SvPVX(sv_2mortal(newSVpvf("Unknown command %s", command))), "HY000");
    XSRETURN_NO;
  }
  if (retval)
  {
    mariadb_dr_do_error(SvOK(dbh) ? dbh : drh, mysql_errno(sock),
             mysql_error(sock) ,mysql_sqlstate(sock));
  }

  if (SvOK(dbh))
  {
    mysql_close(sock);
  }
  if (retval)
    XSRETURN_NO;
  else 
    XSRETURN_YES;
}


MODULE = DBD::MariaDB    PACKAGE = DBD::MariaDB::db


void
type_info_all(dbh)
  SV* dbh
  PPCODE:
{
  /* 	static AV* types = NULL; */
  /* 	if (!types) { */
  /* 	    D_imp_dbh(dbh); */
  /* 	    if (!(types = dbd_db_type_info_all(dbh, imp_dbh))) { */
  /* 	        croak("Cannot create types array (out of memory?)"); */
  /* 	    } */
  /* 	} */
  /* 	ST(0) = sv_2mortal(newRV_inc((SV*) types)); */
  D_imp_dbh(dbh);
  ASYNC_CHECK_XS(dbh);
  ST(0) = sv_2mortal(newRV_noinc((SV*) mariadb_db_type_info_all(dbh,
                                                            imp_dbh)));
  XSRETURN(1);
}


void
_ListDBs(dbh)
  SV*	dbh
  PPCODE:
  MYSQL_RES* res;
  MYSQL_FIELD* field;
  MYSQL_ROW cur;

  D_imp_dbh(dbh);

  ASYNC_CHECK_XS(dbh);

  bool enable_utf8 = (imp_dbh->enable_utf8 || imp_dbh->enable_utf8mb4);

  res = mysql_list_dbs(imp_dbh->pmysql, NULL);
  if (!res  &&
      (!mariadb_db_reconnect(dbh)  ||
       !(res = mysql_list_dbs(imp_dbh->pmysql, NULL))))
{
  mariadb_dr_do_error(dbh, mysql_errno(imp_dbh->pmysql),
           mysql_error(imp_dbh->pmysql), mysql_sqlstate(imp_dbh->pmysql));
}
else
{
  field = mysql_fetch_field(res);
  EXTEND(sp, mysql_num_rows(res));
  while ((cur = mysql_fetch_row(res)))
  {
    SV* sv = sv_2mortal(newSVpvn(cur[0], strlen(cur[0])));
#if MYSQL_VERSION_ID >= FIELD_CHARSETNR_VERSION
    if (enable_utf8 && field && charsetnr_is_utf8(field->charsetnr))
#else
    if (enable_utf8 && field && !(field->flags & BINARY_FLAG))
#endif
      sv_utf8_decode(sv);
    PUSHs(sv);
  }
  mysql_free_result(res);
}


void
do(dbh, statement, attr=Nullsv, ...)
  SV *        dbh
  SV *	statement
  SV *        attr
  PROTOTYPE: $$;$@
  CODE:
{
  D_imp_dbh(dbh);
  int num_params= (items > 3 ? items - 3 : 0);
  int i;
  int retval;
  STRLEN slen;
  char *str_ptr;
  struct imp_sth_ph_st* params= NULL;
  MYSQL_RES* result= NULL;
  bool async= FALSE;
  bool enable_utf8 = (imp_dbh->enable_utf8 || imp_dbh->enable_utf8mb4);
#if MYSQL_VERSION_ID >= MULTIPLE_RESULT_SET_VERSION
  int next_result_rc;
#endif
#if MYSQL_VERSION_ID >= SERVER_PREPARE_VERSION
  int             has_binded;
  int             use_server_side_prepare= 0;
  int             disable_fallback_for_server_prepare= 0;
  MYSQL_STMT      *stmt= NULL;
  MYSQL_BIND      *bind= NULL;
  STRLEN          blen;
#endif
    ASYNC_CHECK_XS(dbh);
#if MYSQL_VERSION_ID >= MULTIPLE_RESULT_SET_VERSION
    while (mysql_next_result(imp_dbh->pmysql)==0)
    {
      MYSQL_RES* res = mysql_use_result(imp_dbh->pmysql);
      if (res)
        mysql_free_result(res);
      }
#endif
  if (SvMAGICAL(statement))
    mg_get(statement);
  for (i = 0; i < num_params; i++)
  {
    SV *param= ST(i+3);
    if (SvMAGICAL(param))
      mg_get(param);
  }
  (void)hv_store((HV*)SvRV(dbh), "Statement", 9, SvREFCNT_inc(statement), 0);
  mariadb_dr_get_statement(aTHX_ statement, enable_utf8, &str_ptr, &slen);
#if MYSQL_VERSION_ID >= SERVER_PREPARE_VERSION
  /*
   * Globaly enabled using of server side prepared statement
   * for dbh->do() statements. It is possible to force driver
   * to use server side prepared statement mechanism by adding
   * 'mariadb_server_prepare' attribute to do() method localy:
   * $dbh->do($stmt, {mariadb_server_prepare=>1});
  */
  use_server_side_prepare = imp_dbh->use_server_side_prepare;
  if (attr)
  {
    SV** svp;
    DBD_ATTRIBS_CHECK("do", dbh, attr);
    svp = DBD_ATTRIB_GET_SVP(attr, "mariadb_server_prepare", strlen("mariadb_server_prepare"));

    use_server_side_prepare = (svp) ?
      SvTRUE(*svp) : imp_dbh->use_server_side_prepare;

    svp = DBD_ATTRIB_GET_SVP(attr, "mariadb_server_prepare_disable_fallback", strlen("mariadb_server_prepare_disable_fallback"));
    disable_fallback_for_server_prepare = (svp) ?
      SvTRUE(*svp) : imp_dbh->disable_fallback_for_server_prepare;
  }
  if (DBIc_DBISTATE(imp_dbh)->debug >= 2)
    PerlIO_printf(DBIc_LOGPIO(imp_dbh),
                  "mysql.xs do() use_server_side_prepare %d\n",
                  use_server_side_prepare);
#endif
  if (attr)
  {
    SV** svp;
    svp   = DBD_ATTRIB_GET_SVP(attr, "async", 5);
    async = (svp) ? SvTRUE(*svp) : FALSE;
  }
  if (DBIc_DBISTATE(imp_dbh)->debug >= 2)
    PerlIO_printf(DBIc_LOGPIO(imp_dbh),
                  "mysql.xs do() async %d\n",
                  (async ? 1 : 0));
  if(async) {
#if MYSQL_VERSION_ID >= SERVER_PREPARE_VERSION
    if (disable_fallback_for_server_prepare)
    {
      mariadb_dr_do_error(dbh, ER_UNSUPPORTED_PS,
               "Async option not supported with server side prepare", "HY000");
      XSRETURN_UNDEF;
    }
    use_server_side_prepare = FALSE; /* for now */
#endif
    imp_dbh->async_query_in_flight = imp_dbh;
  }
#if MYSQL_VERSION_ID >= SERVER_PREPARE_VERSION
  if (use_server_side_prepare)
  {
    stmt= mysql_stmt_init(imp_dbh->pmysql);

    if ((mysql_stmt_prepare(stmt, str_ptr, slen))  &&
        (!mariadb_db_reconnect(dbh) ||
         (mysql_stmt_prepare(stmt, str_ptr, slen))))
    {
      /*
        For commands that are not supported by server side prepared
        statement mechanism lets try to pass them through regular API
      */
      if (!disable_fallback_for_server_prepare && mysql_stmt_errno(stmt) == ER_UNSUPPORTED_PS)
      {
        use_server_side_prepare= 0;
      }
      else
      {
        mariadb_dr_do_error(dbh, mysql_stmt_errno(stmt), mysql_stmt_error(stmt)
                 ,mysql_stmt_sqlstate(stmt));
        retval=-2;
      }
      mysql_stmt_close(stmt);
      stmt= NULL;
    }
    else
    {
      /*
        'items' is the number of arguments passed to XSUB, supplied
        by xsubpp compiler, as listed in manpage for perlxs
      */
      if (items > 3)
      {
        /*
          Handle binding supplied values to placeholders assume user has
          passed the correct number of parameters
        */
        Newz(0, bind, (unsigned int) num_params, MYSQL_BIND);

        for (i = 0; i < num_params; i++)
        {
          SV *param= ST(i+3);
          if (SvOK(param))
          {
            mariadb_dr_get_param(aTHX_ param, i+1, enable_utf8, false, (char **)&bind[i].buffer, &blen);
            bind[i].buffer_length= blen;
            bind[i].buffer_type= MYSQL_TYPE_STRING;
          }
          else
          {
            bind[i].buffer= NULL;
            bind[i].buffer_length= 0;
            bind[i].buffer_type= MYSQL_TYPE_NULL;
          }
        }
        has_binded= 0;
      }
      retval = mariadb_st_internal_execute41(dbh,
                                           num_params,
                                           &result,
                                           stmt,
                                           bind,
                                           &has_binded);
      if (bind)
        Safefree(bind);

      mysql_stmt_close(stmt);
      stmt= NULL;

      if (retval == -2) /* -2 means error */
      {
        SV *err = DBIc_ERR(imp_dbh);
        if (!disable_fallback_for_server_prepare && SvIV(err) == ER_UNSUPPORTED_PS)
        {
          use_server_side_prepare = 0;
        }
      }
    }
  }

  if (! use_server_side_prepare)
  {
#endif
    if (items > 3)
    {
      /*  Handle binding supplied values to placeholders	   */
      /*  Assume user has passed the correct number of parameters  */
      Newz(0, params, sizeof(*params)*num_params, struct imp_sth_ph_st);
      for (i= 0;  i < num_params;  i++)
      {
        SV *param= ST(i+3);
        if (SvOK(param))
          mariadb_dr_get_param(aTHX_ param, i+1, enable_utf8, false, &params[i].value, &params[i].len);
        else
          params[i].value= NULL;
        params[i].type= SQL_VARCHAR;
        params[i].utf8= enable_utf8;
      }
    }
    retval = mariadb_st_internal_execute(dbh, str_ptr, slen, attr, num_params,
                                       params, &result, imp_dbh->pmysql, 0);
#if MYSQL_VERSION_ID >=SERVER_PREPARE_VERSION
  }
#endif
  if (params)
    Safefree(params);

  if (result)
  {
    mysql_free_result(result);
    result= 0;
  }
#if MYSQL_VERSION_ID >= MULTIPLE_RESULT_SET_VERSION
  if (retval != -2 && !async) /* -2 means error */
    {
      /* more results? -1 = no, >0 = error, 0 = yes (keep looping) */
      while ((next_result_rc= mysql_next_result(imp_dbh->pmysql)) == 0)
      {
        result = mysql_use_result(imp_dbh->pmysql);
          if (result)
            mysql_free_result(result);
            result = NULL;
          }
          if (next_result_rc > 0)
          {
            if (DBIc_DBISTATE(imp_dbh)->debug >= 2)
              PerlIO_printf(DBIc_LOGPIO(imp_dbh),
                            "\t<- do() ERROR: %s\n",
                            mysql_error(imp_dbh->pmysql));

              mariadb_dr_do_error(dbh, mysql_errno(imp_dbh->pmysql),
                       mysql_error(imp_dbh->pmysql),
                       mysql_sqlstate(imp_dbh->pmysql));
              retval= -2;
          }
    }
#endif
  /* remember that dbd_st_execute must return <= -2 for error	*/
  if (retval == 0)		/* ok with no rows affected	*/
    XST_mPV(0, "0E0");	/* (true but zero)		*/
  else if (retval < -1)	/* -1 == unknown number of rows	*/
    XST_mUNDEF(0);		/* <= -2 means error   		*/
  else
    XST_mIV(0, retval);	/* typically 1, rowcount or -1	*/
}


SV*
ping(dbh)
    SV* dbh;
  PROTOTYPE: $
  CODE:
    {
      int retval;
/* MySQL 5.7 below 5.7.18 is affected by Bug #78778.
 * MySQL 5.7.18 and higher (including 8.0.3) is affected by Bug #89139.
 *
 * Once Bug #89139 is fixed we can adjust the upper bound of this check.
 *
 * https://bugs.mysql.com/bug.php?id=78778
 * https://bugs.mysql.com/bug.php?id=89139 */
#if !defined(MARIADB_BASE_VERSION) && MYSQL_VERSION_ID >= 50718
      unsigned long long insertid;
#endif

      D_imp_dbh(dbh);
      ASYNC_CHECK_XS(dbh);
#if !defined(MARIADB_BASE_VERSION) && MYSQL_VERSION_ID >= 50718
      insertid = mysql_insert_id(imp_dbh->pmysql);
#endif
      retval = (mysql_ping(imp_dbh->pmysql) == 0);
      if (!retval) {
	if (mariadb_db_reconnect(dbh)) {
	  retval = (mysql_ping(imp_dbh->pmysql) == 0);
	}
      }
#if !defined(MARIADB_BASE_VERSION) && MYSQL_VERSION_ID >= 50718
      imp_dbh->pmysql->insert_id = insertid;
#endif
      RETVAL = boolSV(retval);
    }
  OUTPUT:
    RETVAL



void
quote(dbh, str, type=NULL)
    SV* dbh
    SV* str
    SV* type
  PROTOTYPE: $$;$
  PPCODE:
    {
        SV* quoted;

        D_imp_dbh(dbh);
        ASYNC_CHECK_XS(dbh);

        quoted = mariadb_db_quote(dbh, str, type);
	ST(0) = quoted ? sv_2mortal(quoted) : str;
	XSRETURN(1);
    }

void mariadb_fd(dbh)
    SV* dbh
  PPCODE:
    {
        D_imp_dbh(dbh);
        if(imp_dbh->pmysql->net.fd != -1) {
            XSRETURN_IV(imp_dbh->pmysql->net.fd);
        } else {
            XSRETURN_UNDEF;
        }
    }

void mariadb_async_result(dbh)
    SV* dbh
  PPCODE:
    {
        int retval;

        retval = mariadb_db_async_result(dbh, NULL);

        if(retval > 0) {
            XSRETURN_IV(retval);
        } else if(retval == 0) {
            XSRETURN_PV("0E0");
        } else {
            XSRETURN_UNDEF;
        }
    }

void mariadb_async_ready(dbh)
    SV* dbh
  PPCODE:
    {
        int retval;

        retval = mariadb_db_async_ready(dbh);
        if(retval > 0) {
            XSRETURN_YES;
        } else if(retval == 0) {
            XSRETURN_NO;
        } else {
            XSRETURN_UNDEF;
        }
    }

void _async_check(dbh)
    SV* dbh
  PPCODE:
    {
        D_imp_dbh(dbh);
        ASYNC_CHECK_XS(dbh);
        XSRETURN_YES;
    }

MODULE = DBD::MariaDB    PACKAGE = DBD::MariaDB::st

int
more_results(sth)
    SV *	sth
    CODE:
{
#if (MYSQL_VERSION_ID >= MULTIPLE_RESULT_SET_VERSION)
  D_imp_sth(sth);
  if (mariadb_st_more_results(sth, imp_sth))
  {
    RETVAL=1;
  }
  else
  {
    RETVAL=0;
  }
#else
  PERL_UNUSED_ARG(sth);
  RETVAL=0;
#endif
}
    OUTPUT:
      RETVAL

int
dataseek(sth, pos)
    SV* sth
    int pos
  PROTOTYPE: $$
  CODE:
{
  D_imp_sth(sth);
#if (MYSQL_VERSION_ID >=SERVER_PREPARE_VERSION)
  if (imp_sth->use_server_side_prepare)
  {
    if (imp_sth->use_mysql_use_result || 1)
    {
      if (imp_sth->result && imp_sth->stmt)
      {
        mysql_stmt_data_seek(imp_sth->stmt, pos);
        imp_sth->fetch_done=0;
        RETVAL = 1;
      }
      else
      {
        RETVAL = 0;
        mariadb_dr_do_error(sth, JW_ERR_NOT_ACTIVE, "Statement not active" ,NULL);
      }
    }
    else
    {
      RETVAL = 0;
      mariadb_dr_do_error(sth, JW_ERR_NOT_ACTIVE, "No result set" ,NULL);
    }
  }
  else
  {
#endif
  if (imp_sth->result) {
    mysql_data_seek(imp_sth->result, pos);
    RETVAL = 1;
  } else {
    RETVAL = 0;
    mariadb_dr_do_error(sth, JW_ERR_NOT_ACTIVE, "Statement not active" ,NULL);
  }
#if (MYSQL_VERSION_ID >=SERVER_PREPARE_VERSION) 
  }
#endif
}
  OUTPUT:
    RETVAL

void
rows(sth)
    SV* sth
  CODE:
    D_imp_sth(sth);
    char buf[64];
    D_imp_dbh_from_sth;
    if(imp_dbh->async_query_in_flight) {
        if(mariadb_db_async_result(sth, &imp_sth->result) < 0) {
            XSRETURN_UNDEF;
        }
    }

  /* fix to make rows able to handle errors and handle max value from 
     affected rows.
     if mysql_affected_row returns an error, it's value is 18446744073709551614,
     while a (my_ulonglong)-1 is  18446744073709551615, so we have to add 1 to
     imp_sth->row_num to know if there's an error
  */
  if (imp_sth->row_num+1 ==  (my_ulonglong) -1)
    sprintf(buf, "%d", -1);
  else
    sprintf(buf, "%llu", imp_sth->row_num);

  ST(0) = sv_2mortal(newSVpvn(buf, strlen(buf)));

int mariadb_async_result(sth)
    SV* sth
  CODE:
    {
        D_imp_sth(sth);
        int retval;

        retval= mariadb_db_async_result(sth, &imp_sth->result);

        if(retval > 0) {
            imp_sth->row_num = retval;
            XSRETURN_IV(retval);
        } else if(retval == 0) {
            imp_sth->row_num = retval;
            XSRETURN_PV("0E0");
        } else {
            XSRETURN_UNDEF;
        }
    }
  OUTPUT:
    RETVAL

void mariadb_async_ready(sth)
    SV* sth
  PPCODE:
    {
        int retval;

        retval = mariadb_db_async_ready(sth);
        if(retval > 0) {
            XSRETURN_YES;
        } else if(retval == 0) {
            XSRETURN_NO;
        } else {
            XSRETURN_UNDEF;
        }
    }

void _async_check(sth)
    SV* sth
  PPCODE:
    {
        D_imp_sth(sth);
        D_imp_dbh_from_sth;
        ASYNC_CHECK_XS(sth);
        XSRETURN_YES;
    }


MODULE = DBD::MariaDB    PACKAGE = DBD::MariaDB::GetInfo

# This probably should be grabed out of some ODBC types header file
#define SQL_CATALOG_NAME_SEPARATOR 41
#define SQL_CATALOG_TERM 42
#define SQL_DBMS_VER 18
#define SQL_IDENTIFIER_QUOTE_CHAR 29
#define SQL_MAXIMUM_STATEMENT_LENGTH 105
#define SQL_MAXIMUM_TABLES_IN_SELECT 106
#define SQL_MAX_TABLE_NAME_LEN 35
#define SQL_SERVER_NAME 13
#define SQL_ASYNC_MODE 10021
#define SQL_MAX_ASYNC_CONCURRENT_STATEMENTS 10022

#define SQL_AM_NONE       0
#define SQL_AM_CONNECTION 1
#define SQL_AM_STATEMENT  2


#  dbd_mariadb_get_info()
#  Return ODBC get_info() information that must needs be accessed from C
#  This is an undocumented function that should only
#  be used by DBD::MariaDB::GetInfo.

void
dbd_mariadb_get_info(dbh, sql_info_type)
    SV* dbh
    SV* sql_info_type
  CODE:
    D_imp_dbh(dbh);
    IV type = 0;
    SV* retsv=NULL;
#if !defined(MARIADB_BASE_VERSION) && MYSQL_VERSION_ID >= 50709 && MYSQL_VERSION_ID != 60000
/* MariaDB 10 is not MySQL source level compatible so this only applies to MySQL*/
    IV buffer_len;
#endif 

    if (SvGMAGICAL(sql_info_type))
        mg_get(sql_info_type);

    if (SvOK(sql_info_type))
    	type = SvIV_nomg(sql_info_type);
    else
    {
        mariadb_dr_do_error(dbh, JW_ERR_INVALID_ATTRIBUTE, "get_info called with an invalied parameter", "HY000");
        XSRETURN_UNDEF;
    }
    
    switch(type) {
    	case SQL_CATALOG_NAME_SEPARATOR:
	    /* (dbc->flag & FLAG_NO_CATALOG) ? WTF is in flag ? */
	    retsv = newSVpvn(".",1);
	    break;
	case SQL_CATALOG_TERM:
	    /* (dbc->flag & FLAG_NO_CATALOG) ? WTF is in flag ? */
	    retsv = newSVpvn("database",8);
	    break;
	case SQL_DBMS_VER:
	    retsv = newSVpvn(
	        imp_dbh->pmysql->server_version,
		strlen(imp_dbh->pmysql->server_version)
	    );
	    break;
	case SQL_IDENTIFIER_QUOTE_CHAR:
	    retsv = newSVpvn("`", 1);
	    break;
	case SQL_MAXIMUM_STATEMENT_LENGTH:
#if !defined(MARIADB_BASE_VERSION) && MYSQL_VERSION_ID >= 50709 && MYSQL_VERSION_ID != 60000
        /* MariaDB 10 is not MySQL source level compatible so this
           only applies to MySQL*/
	    /* mysql_get_option() was added in mysql 5.7.3 */
	    /* MYSQL_OPT_NET_BUFFER_LENGTH was added in mysql 5.7.9 */
	    mysql_get_option(NULL, MYSQL_OPT_NET_BUFFER_LENGTH, &buffer_len);
	    retsv = newSViv(buffer_len);
#else
	    /* before mysql 5.7.9 use net_buffer_length macro */
	    retsv = newSViv(net_buffer_length);
#endif
	    break;
	case SQL_MAXIMUM_TABLES_IN_SELECT:
	    /* newSViv((sizeof(int) > 32) ? sizeof(int)-1 : 31 ); in general? */
	    retsv= newSViv((sizeof(int) == 64 ) ? 63 : 31 );
	    break;
	case SQL_MAX_TABLE_NAME_LEN:
	    retsv= newSViv(NAME_LEN);
	    break;
	case SQL_SERVER_NAME:
	    retsv= newSVpvn(imp_dbh->pmysql->host_info,strlen(imp_dbh->pmysql->host_info));
	    break;
        case SQL_ASYNC_MODE:
            retsv = newSViv(SQL_AM_STATEMENT);
            break;
        case SQL_MAX_ASYNC_CONCURRENT_STATEMENTS:
            retsv = newSViv(1);
            break;
    	default:
	    mariadb_dr_do_error(dbh, JW_ERR_INVALID_ATTRIBUTE, SvPVX(sv_2mortal(newSVpvf("Unknown SQL Info type %" IVdf, type))), "HY000");
	    XSRETURN_UNDEF;
    }
    ST(0) = sv_2mortal(retsv);
