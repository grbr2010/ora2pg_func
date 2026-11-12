      l_check_id                    erps.ext_checks.check_id@erpdb%TYPE; -- id
      l_check_num                   erps.ext_checks.check_no@erpdb%TYPE; -- number
      l_check_date                  erps.ext_checks.check_date@erpdb%TYPE; -- date
      l_item_id                     erps.ext_items.item_id@erpdb%TYPE;
      l_item_num                    erps.ext_items.item_num@erpdb%TYPE;
      l_item_date                   erps.ext_items.item_date@erpdb%TYPE;
      l_item_kind                   erps.ext_items.kind_code@erpdb%TYPE;

      l_batch_name                  erps.ext_checks.batch_name@erpdb%TYPE;
      l_state                erps.ext_checks.status_code@erpdb%TYPE;

      --l_sys_flag                   erps.ext_params.auto_flag@erpdb%TYPE;
      l_vendor_flag                 erps.ext_vendors.auto_flag@erpdb%TYPE;

      l_gl_date                     erps.ext_items.gl_date@erpdb%TYPE; -- gl date
