CREATE OR REPLACE EDITIONABLE PACKAGE APP."DEMO_PKG"
AS
   PROCEDURE load_items (p_from DATE, p_to DATE);
   FUNCTION check_one (p_ref VARCHAR2) RETURN VARCHAR2;
   PROCEDURE fetch_attrs (p_group VARCHAR2, p_type VARCHAR2);
   FUNCTION НАЙТИ_ТОВАР (p_id NUMBER) RETURN NUMBER;
END DEMO_PKG;
/
CREATE OR REPLACE EDITIONABLE PACKAGE BODY APP."DEMO_PKG"
AS
   PROCEDURE load_items (p_from DATE, p_to DATE)
   IS
      new_item_id   NUMBER;
      l_request     erps.ext_checks.check_id@erpdb%TYPE;
      l_budget      NUMBER;
   BEGIN
      SELECT erps.item_iface_s.NEXTVAL@erpdb
        INTO new_item_id
        FROM DUAL;

      l_request := erps.erp_iface_pkg.request_id@erpdb;

      -- rename groups from the remote dictionary
      UPDATE ГРУППА_ТОВАРОВ st
         SET st.название = (SELECT v.acc_name FROM erps.erp_accounts@erpdb v WHERE v.acc_code = to_char(st.группа))
       WHERE st.группа IN (SELECT v.acc_code FROM erps.erp_accounts@erpdb v);

      erps.erp_budget_pkg.get_budget_data@erpdb (p_from, 'A', 'B', l_budget, l_budget, l_budget, l_budget);

      UPDATE EXTSCH.IMPORT_TBL@ext1 d
         SET DIR_CONDITION = 0
       WHERE d.id = new_item_id;

      INSERT INTO erps.item_log@erpdb (id, dt) VALUES (new_item_id, SYSDATE);
   END load_items;

   FUNCTION check_one (p_ref VARCHAR2) RETURN VARCHAR2
   IS
      l_state   VARCHAR2 (100);
   BEGIN
      l_state :=
         erps.erp_iface_pkg.check_state@erpdb (
            p_ref   => p_ref);
      RETURN l_state;
   END check_one;

   PROCEDURE fetch_attrs (p_group VARCHAR2, p_type VARCHAR2)
   IS
      x_comb   NUMBER;
      x_cat    NUMBER;
      err_msg  VARCHAR2 (4000);
   BEGIN
      erps.erp_iface_pkg.get_item_attrs@erpdb (
         p_cfo                   => p_group,
         p_statya                => p_group,
         x_code_combination_id   => x_comb,
         x_category_id           => x_cat,
         X_ERR_MSG               => err_msg,
         p_inv_type              => p_type);
      erps.erp_iface_pkg.add_group_code@erpdb (p_group);
   END fetch_attrs;

   FUNCTION НАЙТИ_ТОВАР (p_id NUMBER)
      RETURN NUMBER
   IS
      res   NUMBER DEFAULT NULL;
   BEGIN
      SELECT MIN (op.ТОВАР)
        INTO res
        FROM ТОВАР op, ТОВАР op2
       WHERE op.партия = op2.партия
         AND op2.товар = p_id;

      RETURN res;
   END;
END DEMO_PKG;
/
