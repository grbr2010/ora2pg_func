               erps.erp_iface_pkg.get_item_attrs@erpdb (
                  p_cfo                   => ОТДЕЛ_ERP,
                  p_statya                => ГРУППА_ERP,
                  x_code_combination_id   => x_code_combination_id,
                  x_category_id           => x_category_id,
                  X_ERR_MSG               => ERR_MSG,
                  p_inv_type              => item_kind);
