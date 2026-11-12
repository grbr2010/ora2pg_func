CREATE SCHEMA IF NOT EXISTS fdw_erpdb_erps;
CREATE FOREIGN TABLE IF NOT EXISTS fdw_erpdb_erps.erp_accounts (
	acc_code varchar(30) OPTIONS (key 'true'),
	acc_name varchar(240),
	active numeric,
	amt decimal(12,2)
) SERVER erpdb OPTIONS (schema 'ERPS', table 'ERP_ACCOUNTS');

-- TODO dblink ERPDB: no columns for ERPS.ITEM_LOG
