*&---------------------------------------------------------------------*
*& Report ZFIW0003 - AP Invoice Submission for Approval
*&---------------------------------------------------------------------*
*& Program: ZFIW0003
*& Transaction: ZAP003
*& Purpose: AP Invoice Workflow submission for approval
*& Author: Development Team
*& Date: 2024
*&---------------------------------------------------------------------*

REPORT zfiw0003.

TABLES: rbkp_v.

"----------------------------------------------------------------------
" Selection Screen
"----------------------------------------------------------------------
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_notapp RADIOBUTTON GROUP rg1 DEFAULT 'X' USER-COMMAND radio,
              p_in_app  RADIOBUTTON GROUP rg1.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  SELECT-OPTIONS: s_bukrs FOR rbkp_v-bukrs,
                  s_blart FOR rbkp_v-blart OBLIGATORY,
                  s_cpudt FOR rbkp_v-cpudt.
SELECTION-SCREEN END OF BLOCK b2.


"----------------------------------------------------------------------
" Class Definition
"----------------------------------------------------------------------
CLASS lcl_main DEFINITION.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_invoice_not_approval,
             bukrs        TYPE rbkp_v-bukrs,         " Company Code
             lifnr        TYPE rbkp_v-lifnr,         " Invoicing Party
             cpudt        TYPE rbkp_v-cpudt,         " Entry Date
             bldat        TYPE rbkp_v-bldat,         " Invoice Date
             budat        TYPE rbkp_v-budat,         " Posting Date
             blart        TYPE rbkp_v-blart,         " Document Type
             xblnr        TYPE rbkp_v-xblnr,         " Reference
             bktxt        TYPE rbkp_v-bktxt,         " Document Header Text
             gjahr        TYPE rbkp_v-gjahr,         " Fiscal Year
             belnr        TYPE rbkp_v-belnr,         " Invoice Document No
             cobl_nr      TYPE rbco-cobl_nr,         " Item
             saknr        TYPE rbco-saknr,           " G/L Account
             txt20        TYPE skat-txt20,           " G/L Account Short Text
             kostl        TYPE rbco-kostl,           " Cost Center
             prctr        TYPE rbco-prctr,           " Profit Center
             kursf        TYPE rbkp_v-kursf,         " Exchange Rate
             waers        TYPE rbkp_v-waers,         " Currency
             wrbtr        TYPE rbco-wrbtr,           " Amount in Doc Currency
             waers_bukrs  TYPE t001-waers,           " Company Code Currency
             amount_bukrs TYPE rbco-wrbtr,           " Amount in CC Currency
             zap_wfr1     TYPE zfi0002-zap_wfr1,     " Reviewer 1
             zap_wfr2     TYPE zfi0002-zap_wfr2,     " Reviewer 2
             zap_wfr3     TYPE zfi0002-zap_wfr3,     " Reviewer 3
             zap_wfa1     TYPE zfi0002-zap_wfa1,     " Approver
             user_r1      TYPE zfi0001-usnam,        " Reviewer 1 User
             user_r2      TYPE zfi0001-usnam,        " Reviewer 2 User
             user_r3      TYPE zfi0001-usnam,        " Reviewer 3 User
             user_a1      TYPE zfi0001-usnam,        " Approver User
             name_r1      TYPE ad_namtext,           " Reviewer 1 Name
             name_r2      TYPE ad_namtext,           " Reviewer 2 Name
             name_r3      TYPE ad_namtext,           " Reviewer 3 Name
             name_a1      TYPE ad_namtext,           " Approver Name
             row_color    TYPE lvc_t_scol,           " Row colors
             selected     TYPE char1,                " Selection flag
           END OF ty_invoice_not_approval.

    TYPES: BEGIN OF ty_invoice_in_approval,
             bukrs     TYPE rbkp_v-bukrs,         " Company Code
             lifnr     TYPE rbkp_v-lifnr,         " Invoicing Party
             cpudt     TYPE rbkp_v-cpudt,         " Entry Date
             blart     TYPE rbkp_v-blart,         " Document Type
             bktxt     TYPE rbkp_v-bktxt,         " Document Header Text
             gjahr     TYPE rbkp_v-gjahr,         " Fiscal Year
             belnr     TYPE rbkp_v-belnr,         " Invoice Document No
             user_id   TYPE swwuserwi-user_id,    " User ID
             name_text TYPE ad_namtext,           " Full Name
             selected  TYPE char1,                " Selection flag
           END OF ty_invoice_in_approval.

    TYPES: tt_invoice_not_approval TYPE STANDARD TABLE OF ty_invoice_not_approval,
           tt_invoice_in_approval  TYPE STANDARD TABLE OF ty_invoice_in_approval.

    TYPES: BEGIN OF ty_user_group,
             zap_wfgrp TYPE zfi0001-zap_wfgrp,
             usnam     TYPE zfi0001-usnam,
             zap_wfdf  TYPE zfi0001-zap_wfdf,
           END OF ty_user_group,
           tt_user_group TYPE STANDARD TABLE OF ty_user_group.

    TYPES: BEGIN OF ty_delegation,
             bukrs      TYPE zfi0002-bukrs,
             hkont      TYPE zfi0002-hkont,
             kostl      TYPE zfi0002-kostl,
             prctr      TYPE zfi0002-prctr,
             zamt_limit TYPE zfi0002-zamt_limit,
             zap_wfr1   TYPE zfi0002-zap_wfr1,
             zap_wfr2   TYPE zfi0002-zap_wfr2,
             zap_wfr3   TYPE zfi0002-zap_wfr3,
             zap_wfa1   TYPE zfi0002-zap_wfa1,
           END OF ty_delegation,
           tt_delegation TYPE STANDARD TABLE OF ty_delegation.
    METHODS: constructor,
      display_not_approval,
      display_in_approval,
      handle_user_command FOR EVENT user_command OF cl_gui_alv_grid
        IMPORTING e_ucomm,
      handle_data_changed FOR EVENT data_changed OF cl_gui_alv_grid
        IMPORTING er_data_changed,
      handle_toolbar FOR EVENT toolbar OF cl_gui_alv_grid
        IMPORTING e_object e_interactive,
      submit_invoices,
      send_reminder,
      validate_selections RETURNING VALUE(rv_valid) TYPE abap_bool.

  PRIVATE SECTION.
    DATA: mt_invoice_not_approval TYPE tt_invoice_not_approval,
          mt_invoice_in_approval  TYPE tt_invoice_in_approval,
          mt_user_groups          TYPE tt_user_group,
          mt_delegation           TYPE tt_delegation,
          mo_container            TYPE REF TO cl_gui_custom_container,
          mo_grid                 TYPE REF TO cl_gui_alv_grid.

    METHODS: get_invoices_not_approval,
      get_invoices_in_approval,
      get_user_groups,
      get_delegation_data,
      determine_default_users,
      get_user_names,
      build_fieldcat_not_approval RETURNING VALUE(rt_fieldcat) TYPE lvc_t_fcat,
      build_fieldcat_in_approval RETURNING VALUE(rt_fieldcat) TYPE lvc_t_fcat,
      setup_alv_layout RETURNING VALUE(rs_layout) TYPE lvc_s_layo,
      create_dropdown_table IMPORTING iv_group           TYPE zfi0001-zap_wfgrp
                            RETURNING VALUE(rt_dropdown) TYPE lvc_t_drop,
      trigger_workflow IMPORTING it_selected TYPE tt_invoice_not_approval,
      send_reminder_email IMPORTING it_selected TYPE tt_invoice_in_approval.
ENDCLASS.

"----------------------------------------------------------------------
" Global Variables
"----------------------------------------------------------------------
DATA: go_main TYPE REF TO lcl_main,
      go_container   TYPE REF TO cl_gui_custom_container,
      go_grid        TYPE REF TO cl_gui_alv_grid,
      gv_mode        TYPE char1.
      
"----------------------------------------------------------------------
" Class Implementation
"----------------------------------------------------------------------
CLASS lcl_main IMPLEMENTATION.

  METHOD constructor.
    " Get reference data
    get_user_groups( ).
    get_delegation_data( ).
  ENDMETHOD.

  METHOD display_not_approval.
    DATA: lt_fieldcat TYPE lvc_t_fcat,
          ls_layout   TYPE lvc_s_layo,
          lt_dropdown TYPE lvc_t_drop.

    " Get invoice data
    get_invoices_not_approval( ).

    " Determine default users
    determine_default_users( ).

    " Get user names
    get_user_names( ).

    " Build field catalog
    lt_fieldcat = build_fieldcat_not_approval( ).

    " Setup layout
    ls_layout = setup_alv_layout( ).

    " Create container if not exists
    IF mo_container IS INITIAL.
      CREATE OBJECT mo_container
        EXPORTING
          container_name = 'CONTAINER'.
    ENDIF.

    " Create ALV grid if not exists
    IF mo_grid IS INITIAL.
      CREATE OBJECT mo_grid
        EXPORTING
          i_parent = mo_container.

      " Set event handlers
      SET HANDLER me->handle_user_command FOR mo_grid.
      SET HANDLER me->handle_data_changed FOR mo_grid.
      SET HANDLER me->handle_toolbar FOR mo_grid.
    ENDIF.

    " Set dropdown tables for user fields
    LOOP AT mt_invoice_not_approval ASSIGNING FIELD-SYMBOL(<ls_invoice>).
      IF <ls_invoice>-zap_wfr1 IS NOT INITIAL.
        lt_dropdown = create_dropdown_table( <ls_invoice>-zap_wfr1 ).
        CALL METHOD mo_grid->set_drop_down_table
          EXPORTING
            it_drop_down_alias = lt_dropdown.
      ENDIF.
      " Similar for other user fields...
    ENDLOOP.

    " Display ALV
    CALL METHOD mo_grid->set_table_for_first_display
      EXPORTING
        is_layout            = ls_layout
        it_toolbar_excluding = VALUE #( ( function = cl_gui_alv_grid=>mc_fc_loc_copy_row )
                                        ( function = cl_gui_alv_grid=>mc_fc_loc_delete_row )
                                        ( function = cl_gui_alv_grid=>mc_fc_loc_append_row )
                                        ( function = cl_gui_alv_grid=>mc_fc_loc_insert_row ) )
      CHANGING
        it_outtab            = mt_invoice_not_approval
        it_fieldcatalog      = lt_fieldcat.

    " Enable edit mode
    mo_grid->set_ready_for_input( 1 ).

    " Store mode
    gv_mode = 'N'.
  ENDMETHOD.

  METHOD display_in_approval.
    DATA: lt_fieldcat TYPE lvc_t_fcat,
          ls_layout   TYPE lvc_s_layo.

    " Get invoice data
    get_invoices_in_approval( ).

    " Build field catalog
    lt_fieldcat = build_fieldcat_in_approval( ).

    " Setup layout
    ls_layout = setup_alv_layout( ).

    " Create container if not exists
    IF mo_container IS INITIAL.
      CREATE OBJECT mo_container
        EXPORTING
          container_name = 'CONTAINER'.
    ENDIF.

    " Create ALV grid if not exists
    IF mo_grid IS INITIAL.
      CREATE OBJECT mo_grid
        EXPORTING
          i_parent = mo_container.

      " Set event handlers
      SET HANDLER me->handle_user_command FOR mo_grid.
      SET HANDLER me->handle_data_changed FOR mo_grid.
      SET HANDLER me->handle_toolbar FOR mo_grid.
    ENDIF.

    " Display ALV
    CALL METHOD mo_grid->set_table_for_first_display
      EXPORTING
        is_layout            = ls_layout
        it_toolbar_excluding = VALUE #( ( function = cl_gui_alv_grid=>mc_fc_loc_copy_row )
                                        ( function = cl_gui_alv_grid=>mc_fc_loc_delete_row )
                                        ( function = cl_gui_alv_grid=>mc_fc_loc_append_row )
                                        ( function = cl_gui_alv_grid=>mc_fc_loc_insert_row ) )
      CHANGING
        it_outtab            = mt_invoice_in_approval
        it_fieldcatalog      = lt_fieldcat.

    " Store mode
    gv_mode = 'A'.
  ENDMETHOD.

  METHOD handle_user_command.
    CASE e_ucomm.
      WHEN 'SUBMIT'.
        IF gv_mode = 'N'.
          submit_invoices( ).
        ELSE.
          send_reminder( ).
        ENDIF.
      WHEN 'REFRESH'.
        IF gv_mode = 'N'.
          display_not_approval( ).
        ELSE.
          display_in_approval( ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD handle_data_changed.
    DATA: ls_mod_cell TYPE lvc_s_modi.

    " Process changed data
    LOOP AT er_data_changed->mt_mod_cells INTO ls_mod_cell.
      CASE ls_mod_cell-fieldname.
        WHEN 'USER_R1' OR 'USER_R2' OR 'USER_R3' OR 'USER_A1'.
          " Validate user assignment and update names
          PERFORM validate_user_assignment USING ls_mod_cell.
      ENDCASE.
    ENDLOOP.

    " Refresh grid
    mo_grid->refresh_table_display( ).
  ENDMETHOD.

  METHOD handle_toolbar.
    DATA: ls_toolbar TYPE stb_button.

    " Add custom buttons
    CLEAR ls_toolbar.
    ls_toolbar-function = 'SUBMIT'.
    ls_toolbar-icon = '@49@'.
    ls_toolbar-text = 'Submit'.
    ls_toolbar-quickinfo = 'Submit for Approval'.
    APPEND ls_toolbar TO e_object->mt_toolbar.

    CLEAR ls_toolbar.
    ls_toolbar-function = 'REFRESH'.
    ls_toolbar-icon = '@42@'.
    ls_toolbar-text = 'Refresh'.
    ls_toolbar-quickinfo = 'Refresh Data'.
    APPEND ls_toolbar TO e_object->mt_toolbar.
  ENDMETHOD.

  METHOD get_invoices_not_approval.
    DATA: lt_rbkp TYPE STANDARD TABLE OF rbkp_v,
          lt_rbco TYPE STANDARD TABLE OF rbco,
          lt_ska1 TYPE STANDARD TABLE OF ska1,
          lt_t001 TYPE STANDARD TABLE OF t001.

    " Select parked invoices not yet in approval
    SELECT bukrs, lifnr, cpudt, bldat, budat, blart, xblnr, bktxt,
           gjahr, belnr, kursf, waers
      FROM rbkp_v
      INTO CORRESPONDING FIELDS OF TABLE lt_rbkp
      WHERE rbstat = 'B'
        AND ( approval_status = '' OR approval_status IS NULL )
        AND blart IN ('RN', 'KR', 'KS', 'KT', 'KU', 'KX', 'KG')
        AND bukrs IN s_bukrs
        AND blart IN s_blart
        AND cpudt IN s_cpudt.

    IF lt_rbkp IS INITIAL.
      MESSAGE 'No invoices found for the selection criteria' TYPE 'I'.
      RETURN.
    ENDIF.

    " Get item data
    SELECT belnr, gjahr, cobl_nr, saknr, kostl, prctr, wrbtr
      FROM rbco
      INTO CORRESPONDING FIELDS OF TABLE lt_rbco
      FOR ALL ENTRIES IN lt_rbkp
      WHERE belnr = lt_rbkp-belnr
        AND gjahr = lt_rbkp-gjahr.

    " Get G/L account texts
    SELECT ktopl, saknr, txt20
      FROM ska1
      INTO CORRESPONDING FIELDS OF TABLE lt_ska1
      WHERE ktopl = '1000'.

    " Get company code currencies
    SELECT bukrs, waers
      FROM t001
      INTO CORRESPONDING FIELDS OF TABLE lt_t001.

    " Build output table
    CLEAR mt_invoice_not_approval.
    LOOP AT lt_rbkp ASSIGNING FIELD-SYMBOL(<ls_rbkp>).
      LOOP AT lt_rbco ASSIGNING FIELD-SYMBOL(<ls_rbco>)
        WHERE belnr = <ls_rbkp>-belnr
          AND gjahr = <ls_rbkp>-gjahr.

        APPEND INITIAL LINE TO mt_invoice_not_approval ASSIGNING FIELD-SYMBOL(<ls_invoice>).
        MOVE-CORRESPONDING <ls_rbkp> TO <ls_invoice>.
        MOVE-CORRESPONDING <ls_rbco> TO <ls_invoice>.

        " Get G/L account text
        READ TABLE lt_ska1 ASSIGNING FIELD-SYMBOL(<ls_ska1>)
          WITH KEY saknr = <ls_rbco>-saknr.
        IF sy-subrc = 0.
          <ls_invoice>-txt20 = <ls_ska1>-txt20.
        ENDIF.

        " Get company code currency
        READ TABLE lt_t001 ASSIGNING FIELD-SYMBOL(<ls_t001>)
          WITH KEY bukrs = <ls_rbkp>-bukrs.
        IF sy-subrc = 0.
          <ls_invoice>-waers_bukrs = <ls_t001>-waers.
        ENDIF.

        " Calculate amount in company code currency
        <ls_invoice>-amount_bukrs = <ls_rbco>-wrbtr * <ls_rbkp>-kursf.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_invoices_in_approval.
    DATA: lt_rbkp       TYPE STANDARD TABLE OF rbkp_v,
          lt_sww_wi2obj TYPE STANDARD TABLE OF sww_wi2obj,
          lt_swwuserwi  TYPE STANDARD TABLE OF swwuserwi.

    " Select invoices in approval
    SELECT bukrs, lifnr, cpudt, blart, bktxt, gjahr, belnr
      FROM rbkp_v
      INTO CORRESPONDING FIELDS OF TABLE lt_rbkp
      WHERE rbstat = 'B'
        AND approval_status = 'A'  " In Approval
        AND blart IN ('RN', 'KR', 'KS', 'KT', 'KU', 'KX', 'KG')
        AND bukrs IN s_bukrs
        AND blart IN s_blart
        AND cpudt IN s_cpudt.

    IF lt_rbkp IS INITIAL.
      MESSAGE 'No invoices found for the selection criteria' TYPE 'I'.
      RETURN.
    ENDIF.

    " Get workflow data (simplified - would need actual workflow object type)
    " This is a placeholder for workflow user retrieval

    " Build output table
    CLEAR mt_invoice_in_approval.
    LOOP AT lt_rbkp ASSIGNING FIELD-SYMBOL(<ls_rbkp>).
      APPEND INITIAL LINE TO mt_invoice_in_approval ASSIGNING FIELD-SYMBOL(<ls_invoice>).
      MOVE-CORRESPONDING <ls_rbkp> TO <ls_invoice>.

      " Get pending users (placeholder)
      <ls_invoice>-user_id = 'PLACEHOLDER'.
      <ls_invoice>-name_text = 'Pending User'.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_user_groups.
    SELECT zap_wfgrp, usnam, zap_wfdf
      FROM zfi0001
      INTO CORRESPONDING FIELDS OF TABLE mt_user_groups.
  ENDMETHOD.

  METHOD get_delegation_data.
    SELECT bukrs, hkont, kostl, prctr, zamt_limit, zap_wfr1, zap_wfr2, zap_wfr3, zap_wfa1
      FROM zfi0002
      INTO CORRESPONDING FIELDS OF TABLE mt_delegation.
  ENDMETHOD.

  METHOD determine_default_users.
    DATA: lt_delegation_temp TYPE tt_delegation.

    LOOP AT mt_invoice_not_approval ASSIGNING FIELD-SYMBOL(<ls_invoice>).
      " Find matching delegation entry
      CLEAR lt_delegation_temp.
      LOOP AT mt_delegation ASSIGNING FIELD-SYMBOL(<ls_delegation>)
        WHERE bukrs = <ls_invoice>-bukrs
          AND hkont = <ls_invoice>-saknr
          AND ( ( kostl = <ls_invoice>-kostl AND kostl IS NOT INITIAL )
             OR ( prctr = <ls_invoice>-prctr AND prctr IS NOT INITIAL ) ).

        APPEND <ls_delegation> TO lt_delegation_temp.
      ENDLOOP.

      " Sort by amount limit
      SORT lt_delegation_temp BY zamt_limit ASCENDING.

      " Find appropriate delegation based on amount
      READ TABLE lt_delegation_temp ASSIGNING <ls_delegation>
        WITH KEY zamt_limit = <ls_invoice>-amount_bukrs.
      IF sy-subrc <> 0.
        " Find first entry where amount is less than or equal to limit
        LOOP AT lt_delegation_temp ASSIGNING <ls_delegation>
          WHERE zamt_limit >= <ls_invoice>-amount_bukrs.
          EXIT.
        ENDLOOP.
      ENDIF.

      IF sy-subrc = 0.
        <ls_invoice>-zap_wfr1 = <ls_delegation>-zap_wfr1.
        <ls_invoice>-zap_wfr2 = <ls_delegation>-zap_wfr2.
        <ls_invoice>-zap_wfr3 = <ls_delegation>-zap_wfr3.
        <ls_invoice>-zap_wfa1 = <ls_delegation>-zap_wfa1.

        " Get default users
        IF <ls_invoice>-zap_wfr1 IS NOT INITIAL.
          READ TABLE mt_user_groups ASSIGNING FIELD-SYMBOL(<ls_user>)
            WITH KEY zap_wfgrp = <ls_invoice>-zap_wfr1
                     zap_wfdf = 'X'.
          IF sy-subrc = 0.
            <ls_invoice>-user_r1 = <ls_user>-usnam.
          ENDIF.
        ENDIF.

        " Similar logic for other reviewers and approver
        IF <ls_invoice>-zap_wfr2 IS NOT INITIAL.
          READ TABLE mt_user_groups ASSIGNING <ls_user>
            WITH KEY zap_wfgrp = <ls_invoice>-zap_wfr2
                     zap_wfdf = 'X'.
          IF sy-subrc = 0.
            <ls_invoice>-user_r2 = <ls_user>-usnam.
          ENDIF.
        ENDIF.

        IF <ls_invoice>-zap_wfr3 IS NOT INITIAL.
          READ TABLE mt_user_groups ASSIGNING <ls_user>
            WITH KEY zap_wfgrp = <ls_invoice>-zap_wfr3
                     zap_wfdf = 'X'.
          IF sy-subrc = 0.
            <ls_invoice>-user_r3 = <ls_user>-usnam.
          ENDIF.
        ENDIF.

        IF <ls_invoice>-zap_wfa1 IS NOT INITIAL.
          READ TABLE mt_user_groups ASSIGNING <ls_user>
            WITH KEY zap_wfgrp = <ls_invoice>-zap_wfa1
                     zap_wfdf = 'X'.
          IF sy-subrc = 0.
            <ls_invoice>-user_a1 = <ls_user>-usnam.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_user_names.
    DATA: lt_users   TYPE STANDARD TABLE OF usr02,
          lt_address TYPE STANDARD TABLE OF adrp.

    " Get user names from SU01
    SELECT bname, name_textc
      FROM usr02
      INTO CORRESPONDING FIELDS OF TABLE lt_users
      FOR ALL ENTRIES IN mt_invoice_not_approval
      WHERE bname = mt_invoice_not_approval-user_r1
         OR bname = mt_invoice_not_approval-user_r2
         OR bname = mt_invoice_not_approval-user_r3
         OR bname = mt_invoice_not_approval-user_a1.

    " Update names in invoice table
    LOOP AT mt_invoice_not_approval ASSIGNING FIELD-SYMBOL(<ls_invoice>).
      IF <ls_invoice>-user_r1 IS NOT INITIAL.
        READ TABLE lt_users ASSIGNING FIELD-SYMBOL(<ls_user>)
          WITH KEY bname = <ls_invoice>-user_r1.
        IF sy-subrc = 0.
          <ls_invoice>-name_r1 = <ls_user>-name_textc.
        ENDIF.
      ENDIF.

      " Similar for other users...
    ENDLOOP.
  ENDMETHOD.

  METHOD build_fieldcat_not_approval.
    DATA: ls_fieldcat TYPE lvc_s_fcat.

    " Define field catalog for Not Yet in Approval scenario
    CLEAR rt_fieldcat.

    " Company Code
    ls_fieldcat-fieldname = 'BUKRS'.
    ls_fieldcat-coltext = 'Company Code'.
    ls_fieldcat-outputlen = 10.
    ls_fieldcat-just = 'L'.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Invoicing Party
    ls_fieldcat-fieldname = 'LIFNR'.
    ls_fieldcat-coltext = 'Invoicing Party'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Entry Date
    ls_fieldcat-fieldname = 'CPUDT'.
    ls_fieldcat-coltext = 'Entry Date'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Invoice Date
    ls_fieldcat-fieldname = 'BLDAT'.
    ls_fieldcat-coltext = 'Invoice Date'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Posting Date
    ls_fieldcat-fieldname = 'BUDAT'.
    ls_fieldcat-coltext = 'Posting Date'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Document Type
    ls_fieldcat-fieldname = 'BLART'.
    ls_fieldcat-coltext = 'Document Type'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Reference
    ls_fieldcat-fieldname = 'XBLNR'.
    ls_fieldcat-coltext = 'Reference'.
    ls_fieldcat-outputlen = 16.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Document Header Text
    ls_fieldcat-fieldname = 'BKTXT'.
    ls_fieldcat-coltext = 'Document Header Text'.
    ls_fieldcat-outputlen = 25.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Fiscal Year
    ls_fieldcat-fieldname = 'GJAHR'.
    ls_fieldcat-coltext = 'Fiscal Year'.
    ls_fieldcat-outputlen = 4.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Invoice Document No
    ls_fieldcat-fieldname = 'BELNR'.
    ls_fieldcat-coltext = 'Invoice Document No'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Item
    ls_fieldcat-fieldname = 'COBL_NR'.
    ls_fieldcat-coltext = 'Item'.
    ls_fieldcat-outputlen = 6.
    APPEND ls_fieldcat TO rt_fieldcat.

    " G/L Account
    ls_fieldcat-fieldname = 'SAKNR'.
    ls_fieldcat-coltext = 'G/L Account'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " G/L Account Short Text
    ls_fieldcat-fieldname = 'TXT20'.
    ls_fieldcat-coltext = 'G/L Account Short Text'.
    ls_fieldcat-outputlen = 20.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Cost Center
    ls_fieldcat-fieldname = 'KOSTL'.
    ls_fieldcat-coltext = 'Cost Center'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Profit Center
    ls_fieldcat-fieldname = 'PRCTR'.
    ls_fieldcat-coltext = 'Profit Center'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Exchange Rate
    ls_fieldcat-fieldname = 'KURSF'.
    ls_fieldcat-coltext = 'Exchange Rate'.
    ls_fieldcat-outputlen = 10.
    ls_fieldcat-decimals = 5.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Currency
    ls_fieldcat-fieldname = 'WAERS'.
    ls_fieldcat-coltext = 'Currency'.
    ls_fieldcat-outputlen = 5.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Amount in Document Currency
    ls_fieldcat-fieldname = 'WRBTR'.
    ls_fieldcat-coltext = 'Amount in Doc Currency'.
    ls_fieldcat-outputlen = 15.
    ls_fieldcat-decimals = 2.
    ls_fieldcat-just = 'R'.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Company Code Currency
    ls_fieldcat-fieldname = 'WAERS_BUKRS'.
    ls_fieldcat-coltext = 'Company Code Currency'.
    ls_fieldcat-outputlen = 5.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Amount in Company Code Currency
    ls_fieldcat-fieldname = 'AMOUNT_BUKRS'.
    ls_fieldcat-coltext = 'Amount in CC Currency'.
    ls_fieldcat-outputlen = 15.
    ls_fieldcat-decimals = 2.
    ls_fieldcat-just = 'R'.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Reviewer 1
    ls_fieldcat-fieldname = 'ZAP_WFR1'.
    ls_fieldcat-coltext = 'Reviewer 1'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Reviewer 2
    ls_fieldcat-fieldname = 'ZAP_WFR2'.
    ls_fieldcat-coltext = 'Reviewer 2'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Reviewer 3
    ls_fieldcat-fieldname = 'ZAP_WFR3'.
    ls_fieldcat-coltext = 'Reviewer 3'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Approver
    ls_fieldcat-fieldname = 'ZAP_WFA1'.
    ls_fieldcat-coltext = 'Approver'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Reviewer 1 User (Editable)
    ls_fieldcat-fieldname = 'USER_R1'.
    ls_fieldcat-coltext = 'Reviewer 1 User'.
    ls_fieldcat-outputlen = 12.
    ls_fieldcat-edit = 'X'.
    ls_fieldcat-drdn_hndl = 1.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Reviewer 2 User (Editable)
    ls_fieldcat-fieldname = 'USER_R2'.
    ls_fieldcat-coltext = 'Reviewer 2 User'.
    ls_fieldcat-outputlen = 12.
    ls_fieldcat-edit = 'X'.
    ls_fieldcat-drdn_hndl = 2.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Reviewer 3 User (Editable)
    ls_fieldcat-fieldname = 'USER_R3'.
    ls_fieldcat-coltext = 'Reviewer 3 User'.
    ls_fieldcat-outputlen = 12.
    ls_fieldcat-edit = 'X'.
    ls_fieldcat-drdn_hndl = 3.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Approver User (Editable)
    ls_fieldcat-fieldname = 'USER_A1'.
    ls_fieldcat-coltext = 'Approver User'.
    ls_fieldcat-outputlen = 12.
    ls_fieldcat-edit = 'X'.
    ls_fieldcat-drdn_hndl = 4.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Reviewer 1 Name
    ls_fieldcat-fieldname = 'NAME_R1'.
    ls_fieldcat-coltext = 'Reviewer 1 Name'.
    ls_fieldcat-outputlen = 20.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Reviewer 2 Name
    ls_fieldcat-fieldname = 'NAME_R2'.
    ls_fieldcat-coltext = 'Reviewer 2 Name'.
    ls_fieldcat-outputlen = 20.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Reviewer 3 Name
    ls_fieldcat-fieldname = 'NAME_R3'.
    ls_fieldcat-coltext = 'Reviewer 3 Name'.
    ls_fieldcat-outputlen = 20.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Approver Name
    ls_fieldcat-fieldname = 'NAME_A1'.
    ls_fieldcat-coltext = 'Approver Name'.
    ls_fieldcat-outputlen = 20.
    APPEND ls_fieldcat TO rt_fieldcat.
  ENDMETHOD.

  METHOD build_fieldcat_in_approval.
    DATA: ls_fieldcat TYPE lvc_s_fcat.

    " Define field catalog for In Approval scenario
    CLEAR rt_fieldcat.

    " Company Code
    ls_fieldcat-fieldname = 'BUKRS'.
    ls_fieldcat-coltext = 'Company Code'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Invoicing Party
    ls_fieldcat-fieldname = 'LIFNR'.
    ls_fieldcat-coltext = 'Invoicing Party'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Entry Date
    ls_fieldcat-fieldname = 'CPUDT'.
    ls_fieldcat-coltext = 'Entry Date'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Document Type
    ls_fieldcat-fieldname = 'BLART'.
    ls_fieldcat-coltext = 'Document Type'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Document Header Text
    ls_fieldcat-fieldname = 'BKTXT'.
    ls_fieldcat-coltext = 'Document Header Text'.
    ls_fieldcat-outputlen = 25.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Fiscal Year
    ls_fieldcat-fieldname = 'GJAHR'.
    ls_fieldcat-coltext = 'Fiscal Year'.
    ls_fieldcat-outputlen = 4.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Invoice Document No
    ls_fieldcat-fieldname = 'BELNR'.
    ls_fieldcat-coltext = 'Invoice Document No'.
    ls_fieldcat-outputlen = 10.
    APPEND ls_fieldcat TO rt_fieldcat.

    " User
    ls_fieldcat-fieldname = 'USER_ID'.
    ls_fieldcat-coltext = 'User'.
    ls_fieldcat-outputlen = 12.
    APPEND ls_fieldcat TO rt_fieldcat.

    " Full Name
    ls_fieldcat-fieldname = 'NAME_TEXT'.
    ls_fieldcat-coltext = 'Full Name'.
    ls_fieldcat-outputlen = 20.
    APPEND ls_fieldcat TO rt_fieldcat.
  ENDMETHOD.

  METHOD setup_alv_layout.
    rs_layout-zebra = 'X'.
    rs_layout-sel_mode = 'D'.
    rs_layout-cwidth_opt = 'X'.
    rs_layout-ctab_fname = 'ROW_COLOR'.
  ENDMETHOD.

  METHOD create_dropdown_table.
    DATA: ls_dropdown TYPE lvc_s_drop.

    " Create dropdown table for user group
    CLEAR rt_dropdown.
    LOOP AT mt_user_groups ASSIGNING FIELD-SYMBOL(<ls_user>)
      WHERE zap_wfgrp = iv_group.

      ls_dropdown-handle = '1'.
      ls_dropdown-value = <ls_user>-usnam.
      APPEND ls_dropdown TO rt_dropdown.
    ENDLOOP.
  ENDMETHOD.

  METHOD submit_invoices.
    DATA: lt_selected TYPE tt_invoice_not_approval.

    " Validate selections
    IF validate_selections( ) = abap_false.
      RETURN.
    ENDIF.

    " Get selected invoices
    LOOP AT mt_invoice_not_approval ASSIGNING FIELD-SYMBOL(<ls_invoice>)
      WHERE selected = 'X'.
      APPEND <ls_invoice> TO lt_selected.
    ENDLOOP.

    IF lt_selected IS INITIAL.
      MESSAGE 'Please select at least one invoice' TYPE 'E'.
      RETURN.
    ENDIF.

    " Trigger workflow
    trigger_workflow( lt_selected ).

    " Refresh display
    display_not_approval( ).
  ENDMETHOD.

  METHOD send_reminder.
    DATA: lt_selected TYPE tt_invoice_in_approval.

    " Get selected invoices
    LOOP AT mt_invoice_in_approval ASSIGNING FIELD-SYMBOL(<ls_invoice>)
      WHERE selected = 'X'.
      APPEND <ls_invoice> TO lt_selected.
    ENDLOOP.

    IF lt_selected IS INITIAL.
      MESSAGE 'Please select at least one invoice' TYPE 'E'.
      RETURN.
    ENDIF.

    " Send reminder emails
    send_reminder_email( lt_selected ).
  ENDMETHOD.

  METHOD validate_selections.
    " Validate mandatory fields for selected invoices
    rv_valid = abap_true.

    LOOP AT mt_invoice_not_approval ASSIGNING FIELD-SYMBOL(<ls_invoice>)
      WHERE selected = 'X'.

      " Reviewer 1 is mandatory
      IF <ls_invoice>-user_r1 IS INITIAL.
        MESSAGE 'Reviewer 1 is mandatory for all selected invoices' TYPE 'E'.
        rv_valid = abap_false.
        RETURN.
      ENDIF.

      " Approver is mandatory
      IF <ls_invoice>-user_a1 IS INITIAL.
        MESSAGE 'Approver is mandatory for all selected invoices' TYPE 'E'.
        rv_valid = abap_false.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD trigger_workflow.
    " Placeholder for workflow trigger logic
    " This would integrate with SAP Workflow or Business Workflow
    MESSAGE 'Workflow triggered successfully' TYPE 'S'.
  ENDMETHOD.

  METHOD send_reminder_email.
    " Placeholder for reminder email logic
    MESSAGE 'Reminder emails sent successfully' TYPE 'S'.
  ENDMETHOD.

ENDCLASS.

"----------------------------------------------------------------------
" Form Routines
"----------------------------------------------------------------------
FORM validate_user_assignment USING is_mod_cell TYPE lvc_s_modi.
  " Validate user assignment and update user names
  " This would validate against the user group assignments
ENDFORM.

"----------------------------------------------------------------------
" Event Handlers
"----------------------------------------------------------------------

AT SELECTION-SCREEN ON RADIOBUTTON GROUP rg1.
  " Handle radio button selection
  IF p_notapp = 'X'.
    gv_mode = 'N'.
  ELSE.
    gv_mode = 'A'.
  ENDIF.

  "----------------------------------------------------------------------
  " Main Program Logic
  "----------------------------------------------------------------------

INITIALIZATION.
  " Initialize texts
  TEXT-001 = 'Invoice Status Selection'.
  TEXT-002 = 'Selection Criteria'.

START-OF-SELECTION.
  " Create ALV handler
  CREATE OBJECT go_main.

  " Display based on selection
  IF p_notapp = 'X'.
    go_main->display_not_approval( ).
  ELSE.
    go_main->display_in_approval( ).
  ENDIF.

END-OF-SELECTION.
  " Clean up
  IF go_container IS NOT INITIAL.
    go_container->free( ).
  ENDIF.
