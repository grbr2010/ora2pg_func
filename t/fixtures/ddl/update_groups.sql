           -- 2.1. Изменение наименований статей
           UPDATE ГРУППА_ТОВАРОВ st
              SET st.название = (SELECT v.acc_name FROM erps.erp_accounts@erpdb v where v.acc_code = to_char(st.группа))
            where st.группа in
              (
               select v.acc_code
               from erps.erp_accounts@erpdb v where nvl(v.acc_name,'*****') <> nvl(st.название,'*****')
              );
