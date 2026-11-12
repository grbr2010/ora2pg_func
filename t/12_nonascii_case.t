use utf8;
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/lib";
use DblinkTest qw(convert norm);

binmode(Test::More->builder->$_, ':utf8') for qw(output failure_output todo_output);

# Unquoted non-ASCII identifiers are lower-cased (PG folds only ASCII), like the exported table names.
my ($out) = convert("BEGIN\nSELECT MAX(op.ТОВАР), Количество INTO x, y FROM ТОВАР op, Склад_ERP s WHERE op.партия = s.ПАРТИЯ AND op.Id = 1;\nEND;");
$out = norm($out);
like($out, qr/SELECT MAX\(op\.товар\), количество INTO STRICT x, y FROM товар op, склад_erp s WHERE op\.партия = s\.партия AND op\.Id = 1/, 'unquoted: Cyrillic lower, ASCII untouched');

# literals, comments and quoted names stay as they are
($out) = convert("BEGIN\n-- ТОВАР в комментарии\nSELECT 'ТОВАР' , \"ТОВАР\" FROM Т;\nEND;");
$out = norm($out);
like($out, qr/-- ТОВАР в комментарии/, 'comment kept');
like($out, qr/PERFORM 'ТОВАР' , "ТОВАР" FROM т;/, 'literal and quoted name kept');

# the remote part of a dblink call is not touched (Oracle side)
($out) = convert("BEGIN\nSELECT ЦЕНА INTO x FROM erps.erp_prices\@erpdb WHERE ГРУППА = 1;\nEND;", dblink_signatures => "$Bin/fixtures/dblink_signatures.txt");
like(norm($out), qr/INTO STRICT x FROM fdw_erpdb_erps\.erp_prices WHERE группа = 1/i, 'local part lower-cased');

# PRESERVE_CASE: nothing is changed
($out) = convert("BEGIN\nSELECT ТОВАР INTO STRICT x FROM ТОВАР;\nEND;", preserve_case => 1);
like(norm($out), qr/SELECT ТОВАР INTO STRICT x FROM ТОВАР;/, 'preserve_case: unchanged');

done_testing;
