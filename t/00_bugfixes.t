use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);

use Ora2Pg;

# USE_ORAFCE 1 must leave decode() to orafce instead of rewriting it as CASE
for my $orafce (0, 1)
{
	my $o = bless { type => 'FUNCTION', use_orafce => $orafce, plsql_pgsql => 1,
			text_values => {}, function_metadata => {} }, 'Ora2Pg';
	my $out = Ora2Pg::PLSQL::convert_plsql_code($o, 'x := decode(a, 1, 2, 3);');
	if ($orafce) {
		like($out, qr/decode\(a, 1, 2, 3\)/, 'USE_ORAFCE 1 keeps decode()');
	} else {
		like($out, qr/CASE WHEN a=1 THEN\s+2\s+ELSE 3 END/, 'USE_ORAFCE 0 rewrites decode() to CASE');
	}
}

# Foreign server names for database links
my @names = (
	[ 'RDB1',             undef,     'rdb1',             'plain link' ],
	[ 'APPQ.WORD',    undef,     'appq',         'global name domain is dropped' ],
	[ 'SRCDB@XX_TESTUSER', undef,     'srcdb_xx_testuser', 'connection qualifier kept as suffix' ],
	[ 'LINKB@REMUSR',      undef,     'linkb_remusr',      'qualifier distinguishes links' ],
	[ 'APP.RDB1',     'APP', 'rdb1',             'owner prefix from _get_dblink is removed' ],
	[ 'APP.RDB1',     'SW',     'app',          'only the real owner is stripped' ],
	[ '"DBB_BAK"',      undef,     'dbb_bak',        'quotes removed' ],
	[ 'DBB-X',          undef,     '"dbb-x"',        'non identifier name is quoted' ],
);
is(Ora2Pg::PLSQL::dblink_server_name($_->[0], $_->[1]), $_->[2], $_->[3]) for @names;

# read_dblink_from_file must record the schema as the link owner
my ($fh, $file) = tempfile(SUFFIX => '.sql', UNLINK => 1);
print $fh "CREATE DATABASE LINK RDB1 CONNECT TO REMUSR IDENTIFIED BY secret USING 'SRCDB';\n";
print $fh "CREATE PUBLIC DATABASE LINK OTHERDB USING 'otherdb';\n";
close $fh;
my $o = bless { input_file => $file, schema => 'APP' }, 'Ora2Pg';
$o->read_dblink_from_file();
is($o->{dblink}{RDB1}{owner}, 'APP', 'CONNECT TO link: owner is the schema');
is($o->{dblink}{RDB1}{host},  'SRCDB',    'CONNECT TO link: host parsed');
is($o->{dblink}{OTHERDB}{owner}, 'APP', 'USING-only link: owner is the schema');

# SYSDATE inside parentheses of a parameter default (TRUNC (SYSDATE)) must be converted too
{
	my $o = bless { type => 'PACKAGE', use_orafce => 1, plsql_pgsql => 1, text_values => {}, comment_values => {},
			function_metadata => {}, preserve_case => 0, pg_supports_procedure => 1, pg_supports_outparam => 1,
			package_as_schema => 0, data_type => { %Ora2Pg::Oracle::SQL_TYPE }, pg_integer_type => 1, pg_numeric_type => 1,
			default_numeric => 'bigint' }, 'Ora2Pg';
	my $f = "FUNCTION F1 (a IN NUMBER, d IN DATE DEFAULT TRUNC (SYSDATE), n IN NUMBER(10) DEFAULT NULL) RETURN VARCHAR2 IS\nBEGIN\n RETURN 'x';\nEND F1;\n";
	my $out = $o->_convert_function('APP', $f, 'PKG');
	unlike($out, qr/SYSDATE/i, 'SYSDATE in parameter default converted');
	like($out, qr/DEFAULT TRUNC\(clock_timestamp\(\)\)/, 'default converted');
	like($out, qr/n bigint DEFAULT NULL/, 'other parameter kept');
}

# a package variable registered twice (spec and body) keeps a single default
{
	my $o = bless { type => 'PACKAGE', use_orafce => 1, plsql_pgsql => 1, text_values => {}, comment_values => {},
			function_metadata => {}, global_variables => {}, data_type => { %Ora2Pg::Oracle::SQL_TYPE } }, 'Ora2Pg';
	for my $call (1, 2) {
		my $decl = "VAL_ CONSTANT VARCHAR2(3) := 'RUR';";
		$o->_remove_text_constant_part(\$decl);
		$o->register_global_variable('pk', $decl);
	}
	is($o->{global_variables}{'pk.val_'}{default}, 'RUR', 'global variable default not doubled');
}

# an index named like a table gets a suffix (one relation namespace in PostgreSQL)
{
	my $o = bless { indexes_renaming => 0, indexes_suffix => '', tables => { 'APP.CURRENCY' => {}, 'APP.ORDERS' => {} },
			preserve_case => 0, type => 'TABLE' }, 'Ora2Pg';
	is($o->get_indexname('APP.ORDERS', 'APP.CURRENCY', 'CURRENCY'), 'currency_idx', 'index named like a table is renamed');
	is($o->get_indexname('APP.ORDERS', 'APP.CURRENCY_FACT', 'X'), 'currency_fact', 'other index names untouched');
}

# outer join with a constant and a trailing comment: "col(+) = 1 -- text"
{
	use FindBin qw($Bin);
	use lib "$Bin/lib";
	require DblinkTest;
	my ($out) = DblinkTest::convert("SELECT u.a FROM usr u, addr ad, terr tr WHERE ad.cd_u(+) = u.cd_u\n  AND ad.code_type(+) = 1   -- legal\n  AND tr.code(+) = ad.code",
		type => 'VIEW', use_orafce => 1, idxcomment => 0, dblink_mode => 'off');
	like($out, qr/ON \(u\.cd_u = ad\.cd_u AND 1 = ad\.code_type\)/, 'constant condition stays in ON');
	unlike($out, qr/AND\s+=|\bWHERE\b/, 'no empty operand, no dangling WHERE');
	like($out, qr/-- legal/, 'comment kept');
}

# a TODO marker before a table of the FROM list survives the outer join rewrite
{
	my ($out) = DblinkTest::convert('SELECT a.x FROM app.t a, s.u@ext1 b, c WHERE b.k(+) = a.k AND c.z(+) = a.z',
		type => 'VIEW', use_orafce => 1, idxcomment => 0, dblink_exclude => { EXT1 => 1 });
	like($out, qr{LEFT OUTER JOIN /\* TODO dblink EXT1 \*/ s\.u\@ext1 b ON \(a\.k = b\.k\)}, 'TODO marker kept with its table');
	unlike($out, qr{/\* todo,}, 'marker not taken for a table name');
}

done_testing();
