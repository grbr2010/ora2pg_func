use strict;
use warnings;
use utf8;
use Test::More;
use Ora2Pg::DbLink qw(scan_refs balanced_args bind_text);

sub kinds { join ',', map { $_->{kind} } @_ }

# 1
my @r = scan_refs('l_check_id erps.ext_checks.check_id@erpdb%TYPE;');
is(scalar(@r), 1, '1: one ref');
is($r[0]{kind}, 'type', '1: type');
is($r[0]{path}, 'erps.ext_checks.check_id', '1: path');
is($r[0]{link}, 'ERPDB', '1: link');
# 2
@r = scan_refs('SELECT v.acc_name FROM erps.erp_accounts@erpdb v where v.acc_code = to_char(st.группа)');
is(kinds(@r), 'table', '2: table');
# 3
@r = scan_refs('from wh.doctype@whdb_bak tp,wh.doc@whdb_bak d where wh.rate@whdb_bak(d.cd_vf, d.datef,1)<>0');
is(kinds(@r), 'table,table,call', '3: table,table,call');
# 4
@r = scan_refs('SELECT ap.item_iface_s.NEXTVAL@ERPDB INTO new_item_id FROM DUAL');
is(kinds(@r), 'seq', '4: seq');
is($r[0]{seq_op}, 'NEXTVAL', '4: op');
is($r[0]{path}, 'ap.item_iface_s', '4: path');
# 5
@r = scan_refs('INSERT INTO ap.ap_invoices_interface@ERPDB (item_date, item_id)');
is(kinds(@r), 'table', '5: table not call');
# 6
my $s6 = 'l_state := erps.erp_iface_pkg.check_state@erpdb ( p_ref => l_ref_no);';
@r = scan_refs($s6);
is(kinds(@r), 'call', '6: call');
my ($a6, $e6) = balanced_args($s6, $r[0]{args_start});
is_deeply($a6, [{ name => 'p_ref', expr => 'l_ref_no' }], '6: named arg');
is($e6, $r[0]{args_end}, '6: args_end');
is(substr($s6, $e6), ';', '6: end after )');
# 7
my $s7 = 'SELECT chk_rsv - ERPS.ERP_RESERVE_PKG.CHECK_RESERVE_EXIST@erpdb(num_||?TEXTVALUE0?||z_cur.ТОВАР) INTO chk_rsv FROM dual';
@r = scan_refs($s7);
is(kinds(@r), 'call', '7: call');
my ($a7) = balanced_args($s7, $r[0]{args_start});
is_deeply($a7, [{ expr => 'num_||?TEXTVALUE0?||z_cur.ТОВАР' }], '7: positional cyrillic');
# 8
my $s8 = 'f@erpdb(g(a, b), c => d)';
@r = scan_refs($s8);
my ($a8) = balanced_args($s8, $r[0]{args_start});
is_deeply($a8, [{ expr => 'g(a, b)' }, { name => 'c', expr => 'd' }], '8: args');
# 9
is(scalar(scan_refs('x := 1; %ORA2PG_COMMENT3% y := 2;')), 0, '9: none');
# 10
@r = scan_refs('UPDATE EXTSCH.IMPORT_TBL@ext1 d SET STATUS = 2');
is(kinds(@r), 'table', '10: table');
is($r[0]{link}, 'EXT1', '10: link');
# 11
@r = scan_refs('SELECT a FROM t@WHDB@EXTCUST');
is($r[0]{link}, 'WHDB@EXTCUST', '11: qualified link');
# 12
@r = scan_refs('x := pkg.v@erpdb + 1;');
is(kinds(@r), 'expr', '12: expr');
# 13
is(bind_text('d.datef', 'DATE'), "to_char((d.datef), 'YYYY-MM-DD HH24:MI:SS')", '13: date');
is(bind_text('x', 'NUMBER'), '(x)::text', '13: text');
# extras: nested => is positional; rowtype; masked tokens skipped
my ($ax) = balanced_args('(f(a => 1), b)', 0);
is_deeply($ax, [{ expr => 'f(a => 1)' }, { expr => 'b' }], 'nested => is positional');
@r = scan_refs('r t@erpdb%ROWTYPE; @script.sql ?TEXTVALUE1? %ORA2PG_COMMENT2% a := b => c');
is(kinds(@r), 'rowtype', 'rowtype only');

done_testing;
