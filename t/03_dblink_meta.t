use strict;
use warnings;
use utf8;
use Test::More;
use Ora2Pg::PLSQL ();
use Ora2Pg::DbLink qw(meta);

package Stub;
sub new { bless { sql => [], rows => $_[1] }, $_[0] }
sub selectall_arrayref {
	my ($s, $sql, $attr, @b) = @_;
	push @{$s->{sql}}, $sql;
	for my $k (sort { length($b) <=> length($a) } keys %{$s->{rows}}) {
		next unless index($sql, $k) >= 0;
		my $r = $s->{rows}{$k};
		return ref($r) eq 'CODE' ? $r->(@b) : $r;
	}
	return [];
}
sub errstr { 'stub' }
package Log;
sub logit { push @{$_[0]{log}}, $_[1] }
package main;

my $fx = 't/fixtures/dblink_signatures.txt';
my $c = bless { dblink_signatures => $fx }, 'Log';

is_deeply(meta($c, 'ERPDB', 'COLUMN', 'ERPS.EXT_CHECKS.CHECK_ID'),
	{ type => 'NUMBER', len => 22, precision => 15, scale => 0 }, 'column, case-insensitive');
$c->{dblink_server} = { ERPDB_FLOW => 'erpdb' };
is(meta($c, 'ERPDB_FLOW', 'COLUMN', 'erps.ext_checks.check_id')->{precision}, 15, 'link mapped to a server uses its signatures');
delete $c->{dblink_server}; delete $c->{dblink_meta}{ERPDB_FLOW};
my $t = meta($c, 'ERPDB', 'TABLE', 'erps.erp_accounts');
is($t->{owner}, 'ERPS', 'table owner');
is($t->{name}, 'ERP_ACCOUNTS', 'table name');
is_deeply($t->{pk}, ['ACC_CODE'], 'pk');
is(scalar @{$t->{columns}}, 4, '4 columns');
is_deeply($t->{columns}[1], { name => 'ACC_NAME', type => 'VARCHAR2', len => 240, precision => undef, scale => undef, nullable => 'Y' }, 'varchar column');
is_deeply([@{$t->{columns}[3]}{qw(precision scale nullable)}], [12, 2, 'N'], 'NUMBER(12,2) NOT NULL');
my $f = meta($c, 'ERPDB', 'ROUTINE', 'erps.erp_iface_pkg.check_state');
is($f->{type}, 'FUNCTION', 'function');
is($f->{return}, 'VARCHAR2', 'return');
is_deeply($f->{args}, [ { name => 'p_ref', mode => 'IN', type => 'VARCHAR2' } ], 'function args');
my $p = meta($c, 'ERPDB', 'ROUTINE', 'erps.erp_budget_pkg.get_budget_data');
is($p->{type}, 'PROCEDURE', 'procedure');
is($p->{return}, undef, 'no return');
is(scalar @{$p->{args}}, 7, '7 args');
is($p->{args}[3]{mode}, 'OUT', 'OUT');
is(meta($c, 'ERPDB', 'ROUTINE', 'erps.pkg.upd')->{args}[0]{mode}, 'IN/OUT', 'IN OUT -> IN/OUT');
is(meta($c, 'ERPDB', 'ROUTINE', 'erps.pkg.bad'), undef, 'bad line skipped');
is(scalar(grep { /line (?:10|11)\b/ } @{$c->{log}}), 2, 'warnings carry line numbers');
is(meta($c, 'ERPDB', 'TABLE', 'nope.nope'), undef, 'unknown -> undef');

# live dictionary
my %rows = (
	'FROM DUAL@' => [['ERPS']],
	'all_tab_columns@' => sub { $_[1] eq 'REAL_T' ? [['ID', 'NUMBER', 22, 15, 0, 'N'], ['NM', 'VARCHAR2', 30, undef, undef, 'Y']] : [] },
	'all_synonyms@' => sub { [['OTHER', 'REAL_T', undef, 'PUBLIC'], ['ERPS', 'REAL_T', undef, 'ERPS']] },
	'all_constraints@' => [['ID']],
	'all_arguments@' => sub { $_[2] eq 'OVL' ? [[undef, 0, 'OUT', 'NUMBER', 1], ['A', 1, 'IN', 'NUMBER', 1], ['A', 1, 'IN', 'DATE', 2]]
		: $_[2] eq 'F' ? [[undef, 0, 'OUT', 'NUMBER', undef], ['X', 1, 'IN', 'DATE', undef]] : [] },
);
my $d = Stub->new(\%rows);
my $l = bless { dbh => $d }, 'Log';
my $r = meta($l, 'ERPDB', 'TABLE', 'syn_t');
is($r->{name}, 'REAL_T', 'synonym resolved');
is_deeply($r->{pk}, ['ID'], 'live pk');
is_deeply(meta($l, 'ERPDB', 'COLUMN', 'syn_t.id'), { type => 'NUMBER', len => 22, precision => 15, scale => 0 }, 'live column');
is_deeply(meta($l, 'ERPDB', 'ROUTINE', 'f'), { type => 'FUNCTION', return => 'NUMBER', args => [ { name => 'X', mode => 'IN', type => 'DATE' } ] }, 'live function');
is(meta($l, 'ERPDB', 'ROUTINE', 'ovl'), undef, 'overload -> undef');
ok(scalar(grep { /overload/ } @{$l->{log}}), 'overload warning');
my $n = @{$d->{sql}};
meta($l, 'ERPDB', 'ROUTINE', 'ovl'); meta($l, 'ERPDB', 'TABLE', 'syn_t'); meta($l, 'ERPDB', 'TABLE', 'missing');
my $n2 = @{$d->{sql}};
meta($l, 'ERPDB', 'TABLE', 'missing');
is(scalar @{$d->{sql}}, $n2, 'cache (including undef): no repeated queries');
cmp_ok($n2, '>', $n, 'new objects do query');

# input_file => no queries; bad link name => no queries
$d = Stub->new(\%rows);
my $i = bless { dbh => $d, input_file => 'x.sql' }, 'Log';
is(meta($i, 'ERPDB', 'TABLE', 'syn_t'), undef, 'input_file: undef');
is(scalar @{$d->{sql}}, 0, 'input_file: no queries');
my $b = bless { dbh => $d }, 'Log';
is(meta($b, 'ERPDB; DROP', 'TABLE', 'syn_t'), undef, 'bad link name: undef');
is(scalar @{$d->{sql}}, 0, 'bad link name: no queries');

# query error
my $e = bless { dbh => bless({}, 'Err') }, 'Log';
{ package Err; sub selectall_arrayref { die "ORA-00942\n" } }
is(meta($e, 'ERPDB', 'TABLE', 'x'), undef, 'query error -> undef');
ok(scalar(grep { /WARNING: .*ORA-00942/ } @{$e->{log}}), 'query error warned');

done_testing;
