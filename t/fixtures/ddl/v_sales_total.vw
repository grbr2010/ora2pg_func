--
-- V_SALES_TOTAL  (View)
--
CREATE OR REPLACE FORCE EDITIONABLE VIEW APP.V_SALES_TOTAL
(SM, DATEF)
BEQUEATH DEFINER
AS
select /*+ ordered use_nl(tp)*/sum(decode(d.cd_vf,
                       1, d.fprice,
                       d.fprice/(wh.rate@whdb_bak(d.cd_vf, d.datef,1))
                       ))  Sm, d.datef from wh.doctype@whdb_bak tp,wh.doc@whdb_bak d
                       where upper(tp.fullpathnm) like '%ПРОДАЖ%ИТОГ%'
                         and wh.rate@whdb_bak(d.cd_vf, d.datef,1)<>0
                         and d.tp=tp.cd_c
    Group By d.datef;
