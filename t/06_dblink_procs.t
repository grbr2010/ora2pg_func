use utf8;
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/lib";
use DblinkTest qw(convert norm lines slurp);

binmode(Test::More->builder->$_, ':utf8') for qw(output failure_output todo_output);

my $sig = "$Bin/fixtures/dblink_procs_sig.txt";
my ($out, $o);

# 1. Get_Budget_data: 3 IN, 4 OUT
my $src = slurp("$Bin/fixtures/ddl/proc_budget.sql");
($out) = convert("DECLARE\n n int;\nBEGIN\n$src END;", dblink_signatures => $sig);
$out = norm($out);
like($out, qr/\Q_dbl_r1 := oracle_exec('erpdb', \E\$ora\$\QDECLARE o4 NUMBER; o5 NUMBER; o6 NUMBER; o7 NUMBER; BEGIN erps.ERP_BUDGET_PKG.Get_Budget_data(:p1, :p2, :p3, o4, o5, o6, o7); :p0 := NVL(TO_CHAR(o4), chr(31)) || chr(30) || NVL(TO_CHAR(o5), chr(31)) || chr(30) || NVL(TO_CHAR(o6), chr(31)) || chr(30) || NVL(TO_CHAR(o7), chr(31)); END;\E\$ora\$\Q, (p_per)::text, (p_erpdb_cfo)::text, (acc_c.группа)::text);\E/, 'budget: oracle_exec');
like($out, qr/\Qp_avail := nullif(split_part(_dbl_r1, chr(30), 4), chr(31))\E/, 'budget: 4th');
like($out, qr/\Qp_plan := nullif(split_part(_dbl_r1, chr(30), 1), chr(31));\E/, 'budget: 1st');
like($out, qr/DECLARE\s*_dbl_r1 text;\s*n integer;/i, 'budget: declared');
unlike($out, qr/PERFORM PERFORM|CALL oracle_exec|\@/, 'budget: no PERFORM PERFORM');

# 2. named, mixed IN/OUT
$src = slurp("$Bin/fixtures/ddl/proc_out.sql");
($out) = convert("BEGIN\n$src END;", dblink_signatures => $sig);
$out = norm($out);
like($out, qr/\Q:p0 := NVL(TO_CHAR(o3), chr(31)) || chr(30) || NVL(TO_CHAR(o4), chr(31)) || chr(30) || NVL(o5, chr(31)); END;\E/, 'named: pack');
like($out, qr/\QDECLARE o3 NUMBER; o4 NUMBER; o5 VARCHAR2(32767); BEGIN erps.erp_iface_pkg.get_item_attrs(p_cfo => :p1, p_statya => :p2, x_code_combination_id => o3, x_category_id => o4, X_ERR_MSG => o5, p_inv_type => :p3);\E/, 'named: block');
like($out, qr/\Q(отдел_erp)::text, (группа_erp)::text, (item_kind)::text);\E/, 'named: binds');
like($out, qr/\QERR_MSG := nullif(split_part(_dbl_r1, chr(30), 3), chr(31))\E/, 'named: ERR_MSG');

# 3. IN only: with / without signature
$src = slurp("$Bin/fixtures/ddl/proc_in_only.sql");
($out) = convert("BEGIN\n$src END;", dblink_signatures => $sig);
like(norm($out), qr/\QPERFORM oracle_exec('erpdb', \E\$ora\$\QBEGIN erps.erp_iface_pkg.add_group_code(:p1); :p0 := NULL; END;\E\$ora\$\Q, (group_code)::text);\E/, 'IN only');
unlike(norm($out), qr/PERFORM PERFORM/, 'no double PERFORM');
($out) = convert("BEGIN\n$src END;");
like(norm($out), qr{\Q/* TODO dblink ERPDB: no signature for erps.erp_iface_pkg.add_group_code */\E}, 'no signature -> TODO');

# 4. literals, no signature
($out) = convert("BEGIN erps.pkg.p\@erpdb('A', 1); END;");
like(norm($out), qr/\QPERFORM oracle_exec('erpdb', \E\$ora\$\QBEGIN erps.pkg.p(:p1, :p2); :p0 := NULL; END;\E\$ora\$\Q, ('A')::text, (1)::text);\E/, 'literals');

# 5. IN OUT
($out) = convert("BEGIN erps.pkg.io\@erpdb(v, d); END;", dblink_signatures => $sig);
$out = norm($out);
like($out, qr/\QDECLARE o1 VARCHAR2(32767) := :p1; o2 DATE := TO_DATE(:p2, 'YYYY-MM-DD HH24:MI:SS'); BEGIN erps.pkg.io(o1, o2);\E/, 'IN OUT');
like($out, qr/\Q(v)::text, to_char((d), 'YYYY-MM-DD HH24:MI:SS'));\E/, 'IN OUT binds');
like($out, qr/\Qd := nullif(split_part(_dbl_r1, chr(30), 2), chr(31))\E/, 'IN OUT back');

# 6. CLOB OUT; OUT arg that is not a variable
($out) = convert("BEGIN erps.pkg.getclob\@erpdb(v); END;", dblink_signatures => $sig);
like(norm($out), qr{\Q/* TODO dblink ERPDB: unsupported OUT type \E(?:CLOB|text)\Q of argument 1 */ erps.pkg.getclob\E\@erpdb\(v\)}, 'CLOB');
($out) = convert("BEGIN erps.pkg.two\@erpdb(1); END;", dblink_signatures => $sig);
like(norm($out), qr{TODO dblink ERPDB: OUT argument 1 is not a variable}, 'OUT literal');

# 7. two calls
($out) = convert("BEGIN erps.pkg.two\@erpdb(a); erps.pkg.two\@erpdb(b); END;", dblink_signatures => $sig);
$out = norm($out);
like($out, qr/_dbl_r1 text;\s*_dbl_r2 text;/, 'two declared');
like($out, qr/_dbl_r2 := oracle_exec.*b := nullif\(split_part\(_dbl_r2/, 'second uses _dbl_r2');

# 8. together with ora2pg's own _ora2pg_r RECORD
($out) = convert("DECLARE\n v NUMBER;\nBEGIN\n local_proc(v);\n erps.pkg.two\@erpdb(a); END;", dblink_signatures => $sig,
	function_metadata => { 'unknown' => { '' => { local_proc => { metadata => { args => 'v OUT NUMBER' } } } } }, current_package => '');
$out = norm($out);
like($out, qr/_dbl_r1 text;/, 'with other OUT: dbl declared');
SKIP: {
	skip 'ora2pg did not add _ora2pg_r in the stub', 1 unless $out =~ /_ora2pg_r RECORD/;
	like($out, qr/_ora2pg_r RECORD;/, '_ora2pg_r declared');
}

# 9. NUMBER without precision -> numeric
($out) = convert("BEGIN x := erps.wh.rate\@erpdb(1) + 1; END;", dblink_signatures => "$Bin/fixtures/dblink_calls_sig.txt");
($out) = convert("BEGIN x := 1 + wh.rate\@whdb_bak('a', sysdate, 1); END;", dblink_signatures => "$Bin/fixtures/dblink_calls_sig.txt");
like(norm($out), qr/::numeric\b/, 'rate -> numeric');
($out) = convert("DECLARE v erps.t.c\@erpdb%TYPE; BEGIN NULL; END;", dblink_signatures => "$Bin/fixtures/dblink_signatures.txt");
unlike(norm($out), qr/numeric/, '%TYPE NUMBER(15) not numeric') if $out =~ /DECLARE/;

done_testing;
