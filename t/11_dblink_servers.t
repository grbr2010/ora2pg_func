use utf8;
use strict;
use warnings;
use Test::More;
use File::Temp ();
use Ora2Pg;
use Ora2Pg::DbLink qw(server_for server_name_from_def);

# server = <database>_<login>
is(server_name_from_def('whdb', 'WH'), 'whdb_wh', 'database alias + login');
is(server_name_from_def('WHDB', 'APP'), 'whdb_app', 'case does not matter');
is(server_name_from_def('whdb_bak', 'WH'), 'whdb_bak_wh', 'another database, same login');
is(server_name_from_def('PRODDB', 'EXTCUST'), 'proddb_extcust', 'ERPDB');
is(server_name_from_def('EXT4', '"app"'), 'ext4_app', 'quoted login');
is(server_name_from_def('(DESCRIPTION=(ADDRESS=(HOST=h.x.loc)(PORT=1521))(CONNECT_DATA=(SID=dirsid)))', 'APP'), 'dirsid_app', 'descriptor with SID');
is(server_name_from_def('(DESCRIPTION=(ADDRESS=(HOST=h.x.loc)(PORT=1521)))', 'APP'), undef, 'descriptor without database');
is(server_name_from_def('whdb', undef), undef, 'no login');

my %defs = (
	'WH'      => { owner => 'APP', user => 'APP', host => 'whdb' },
	'WH_PROD' => { owner => 'APP', user => 'APP', host => 'WHDB' },
	'WHDB'    => { owner => 'APP', user => 'WH',     host => 'whdb' },
	'WHDB_BAK'=> { owner => 'APP', user => 'WH',     host => 'whdb_bak' },
	'APP.ERPDB' => { owner => 'APP', user => 'EXTCUST', host => 'PRODDB' },
);
my $o = bless { dblink => \%defs, dblink_server => {} }, 'Ora2Pg';
is(server_for($o, 'WH'), 'whdb_app', 'link WH');
is(server_for($o, 'WH_PROD'), 'whdb_app', 'same database and login: same server');
is(server_for($o, 'WHDB'), 'whdb_wh', 'link WHDB');
is(server_for($o, 'WHDB_BAK'), 'whdb_bak_wh', 'copy of the database: own server');
is(server_for($o, 'ERPDB'), 'proddb_extcust', 'definition keyed with the owner');
is(server_for($o, 'nowhere'), 'nowhere', 'no definition: old name from the link');
$o->{dblink_server} = { WHDB => 'custom' };
is(server_for($o, 'WHDB'), 'custom', 'DBLINK_SERVER wins');

# live dictionary on demand; no query when the input is a file
package Stub { sub new { bless { n => 0 }, shift } sub selectall_arrayref { $_[0]{n}++; return [['EXTCUST', 'PRODDB']] } sub errstr { '' } }
package main;
my $dbh = Stub->new;
my $l = bless { dbh => $dbh, dblink_server => {} }, 'Ora2Pg';
is(server_for($l, 'ERPDB'), 'proddb_extcust', 'definition from ALL_DB_LINKS');
server_for($l, 'ERPDB');
is($dbh->{n}, 1, 'cached');
my $f = bless { dbh => $dbh, input_file => 'x.sql', dblink_server => {} }, 'Ora2Pg';
is(server_for($f, 'ERPDB'), 'erpdb', 'input file: no dictionary, old name');
is($dbh->{n}, 1, 'no query');

# export_dblink: one CREATE SERVER per database and login
my $e = bless { type => 'DBLINK', dblink => { %defs }, dblink_mode => 'fdw', dblink_server => {}, quiet => 1, no_header => 1,
	output_dir => File::Temp::tempdir(CLEANUP => 1), schema => 'APP' }, 'Ora2Pg';
for (values %{$e->{dblink}}) { $_->{username} = $_->{user}; $_->{password} = 'NONE'; }
my $out = '';
{
	no warnings 'redefine';
	local *Ora2Pg::dump = sub { $out .= $_[1] };
	local *Ora2Pg::_set_file_header = sub { '' };
	local *Ora2Pg::save_filetoupdate_list = sub { };
	$e->export_dblink();
}
my @srv = $out =~ /^CREATE SERVER (\S+)/mg;
is_deeply([sort @srv], [qw(proddb_extcust whdb_app whdb_bak_wh whdb_wh)], 'WH and WH_PROD share one server') or diag $out;

done_testing;
