use utf8;
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/lib";
use DblinkTest qw(convert norm lines slurp);

binmode(Test::More->builder->$_, ':utf8') for qw(output failure_output todo_output);

my $sig = "$Bin/fixtures/dblink_signatures.txt";

# 1. pack_erpdb.pkb, first UPDATE of block 2.1
my ($out) = convert(slurp("$Bin/fixtures/ddl/update_groups.sql"), dblink_server => {});
$out = norm($out);
is(() = $out =~ /fdw_erpdb_erps\.erp_accounts/g, 2, 'both subqueries use the foreign table');
unlike($out, qr/\@/, 'no @ left');
like($out, qr/UPDATE ГРУППА_ТОВАРОВ st/i, 'local table untouched');

# 2. view
($out) = convert('select 1 from wh.doctype@whdb_bak tp,wh.doc@whdb_bak d where tp.a=d.a');
like(norm($out), qr/from fdw_whdb_bak_wh\.doctype tp,\s*fdw_whdb_bak_wh\.doc d/i, 'view: two tables on one link');

# 3, 4. sequences
my $nv = q{oracle_scalar('erpdb', $ora$SELECT ap.item_iface_s.NEXTVAL FROM DUAL$ora$)::numeric};
($out) = convert("BEGIN\n" . slurp("$Bin/fixtures/ddl/nextval.sql") . "END;");
like(norm($out), qr/\Q$nv\E/, 'NEXTVAL');
($out) = convert("BEGIN\nx := 1; -- c\n" . slurp("$Bin/fixtures/ddl/currval.sql") . "END;");
$out = norm($out);
like($out, qr/oracle_scalar\('erpdb', \$ora\$SELECT ap\.item_iface_s\.CURRVAL FROM DUAL\$ora\$\)::numeric/, 'CURRVAL');
like($out, qr/-- item_iface_s\.CURRVAL\@ERPDB -- item_id/, 'comment text unchanged');

# 5. %TYPE
my $decl = slurp("$Bin/fixtures/ddl/decl_types.sql");
($out) = convert("DECLARE\n${decl}BEGIN NULL; END;", dblink_signatures => $sig);
$out = norm($out);
like($out, qr/l_check_id (?:bigint|numeric|integer)\b[^;]*;/i, '%TYPE with signature -> PG type');
unlike($out, qr/l_check_id [^;]*TODO/, 'no TODO when signature known');
like($out, qr/l_check_num text \/\* TODO dblink ERPDB: erps\.ext_checks\.check_no%TYPE \*\/;/, '%TYPE without signature');
like($out, qr/--l_sys_flag\s+erps\.ext_params\.auto_flag\@erpdb%TYPE;/, 'commented %TYPE untouched');

# 6. EXCLUDE
($out) = convert(slurp("$Bin/fixtures/ddl/excluded_update.sql"), dblink_exclude => { EXT1 => 1 });
like(norm($out), qr{/\* TODO dblink EXT1 \*/ EXTSCH\.IMPORT_TBL\@ext1 d}, 'EXCLUDE');

# 7. mode off
my $src = "BEGIN SELECT a INTO b FROM erps.t\@erpdb; END;";
my ($off) = convert($src, dblink_mode => 'off');
like(norm($off), qr/erps\.t\@erpdb/, 'off: @erpdb stays');
unlike(norm($off), qr/fdw_/, 'off: no rewrite');
my ($on) = convert($src);
isnt(norm($on), norm($off), 'on differs from off');

# 8. foreign_tables_sql
{
	my ($o, $o2);
	(undef, $o) = convert('SELECT 1 FROM erps.erp_accounts@erpdb v, erps.nosuch@erpdb n', dblink_signatures => $sig);
	my $sql = Ora2Pg::DbLink::foreign_tables_sql($o);
	like($sql, qr/CREATE FOREIGN TABLE IF NOT EXISTS fdw_erpdb_erps\.erp_accounts \(\n\tacc_code varchar\(30\) OPTIONS \(key 'true'\),\n\tacc_name varchar\(240\),\n/, 'columns and key');
	like($sql, qr/\) SERVER erpdb OPTIONS \(schema 'ERPS', table 'ERP_ACCOUNTS'\);/, 'server options');
	like($sql, qr/CREATE SCHEMA IF NOT EXISTS fdw_erpdb_erps;/, 'schema');
	like($sql, qr/^-- TODO dblink ERPDB: no columns for ERPS\.NOSUCH$/m, 'no signature -> TODO');
	unlike($sql, qr/IMPORT FOREIGN/, 'no IMPORT FOREIGN SCHEMA');
}

done_testing;
