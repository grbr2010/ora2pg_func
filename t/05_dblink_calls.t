use utf8;
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/lib";
use DblinkTest qw(convert norm lines slurp);

binmode(Test::More->builder->$_, ':utf8') for qw(output failure_output todo_output);

my $sig = "$Bin/fixtures/dblink_calls_sig.txt";
my ($out, $x);

# 1. named argument -> oracle_exec, assignment without cast
my $exp = q{l_state := oracle_exec('erpdb', $ora$BEGIN :p0 := erps.erp_iface_pkg.check_state(p_ref => :p1); END;$ora$, (l_ref_no)::text);};
($out) = convert("BEGIN\n" . slurp("$Bin/fixtures/ddl/named_call.sql") . "END;");
like(norm($out), qr/\Q$exp\E/, 'named -> oracle_exec');

# 2. cast from the signature / TODO without it
my $src = slurp("$Bin/fixtures/ddl/cast_call.sql");
my $call = q{oracle_call('erpdb', 'ERPS.ERP_RESERVE_PKG.CHECK_RESERVE_EXIST', (num_||'/'||z_cur.ТОВАР)::text)};
($out) = convert("BEGIN\n$src END;", dblink_signatures => $sig);
like(norm($out), qr/\Q$call\E::(?:numeric|bigint|integer|double precision)/, 'cast by RETURN NUMBER');
($out) = convert("BEGIN\n$src END;");
like(norm($out), qr/\Q$call\E \/\* TODO dblink type \*\//, 'no signature -> TODO type');

# 3. view, positional, DATE bind
$src = 'select 1 from t d where wh.rate@whdb_bak(d.cd_vf, d.datef,1)<>0';
($out) = convert($src);
like(norm($out), qr/\Qoracle_call('whdb_bak', 'wh.rate', (d.cd_vf)::text, (d.datef)::text, (1)::text)\E/, 'view call');
($out) = convert($src, dblink_signatures => $sig);
like(norm($out), qr/\Qoracle_call('whdb_bak', 'wh.rate', (d.cd_vf)::text, to_char((d.datef), 'YYYY-MM-DD HH24:MI:SS'), (1)::text)\E/, 'DATE bind');

# 4. nested
($out) = convert("BEGIN x := a.f\@erpdb(a.g\@erpdb(1)); END;");
$out = norm($out);
like($out, qr/\Qx := oracle_call('erpdb', 'a.f', (oracle_call('erpdb', 'a.g', (1)::text)\E/, 'nested');
unlike($out, qr/\@/, 'nested: no @');

# 5. statement call: handled in T6 (t/06_dblink_procs.t)
($out) = convert("BEGIN\napps.pkg.p\@erpdb(1);\nEND;");
like(norm($out), qr/PERFORM oracle_exec\('erpdb'/, 'statement call: oracle_exec (T6)');

# 6. @ in a literal
($out) = convert("BEGIN x := 'a\@b'; END;");
like(norm($out), qr/x := 'a\@b';/, 'literal untouched');

# 7. no args, expr without parens
($out) = convert("BEGIN x := erps.pkg.f\@erpdb(); END;");
like(norm($out), qr/x := oracle_call\('erpdb', 'erps\.pkg\.f'\);/, 'no args');
($out) = convert("BEGIN\n" . slurp("$Bin/fixtures/ddl/expr_call.sql") . "END;");
like(norm($out), qr/l_request_id := oracle_call\('erpdb', 'erps\.erp_iface_pkg\.request_id'\);/, 'expr -> oracle_call');

done_testing;
