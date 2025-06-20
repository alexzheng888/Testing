*&---------------------------------------------------------------------*
*& Report ZPRRP018
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zprrp018.

TABLES: prps, bkpf.
*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_opt1 RADIOBUTTON GROUP opt DEFAULT 'X' USER-COMMAND opt,
              p_opt2 RADIOBUTTON GROUP opt,
              p_opt3 RADIOBUTTON GROUP opt.
SELECTION-SCREEN END OF BLOCK b01.

SELECTION-SCREEN BEGIN OF BLOCK b02 WITH FRAME TITLE TEXT-002.
  SELECT-OPTIONS: s_wbs    FOR prps-posid MATCHCODE OBJECT prpm,
                  s_erdat  FOR prps-erdat.
  PARAMETERS:     p_kostl  TYPE cobrb-kostl MATCHCODE OBJECT kost MODIF ID cc1.
  SELECT-OPTIONS: s_budat  FOR bkpf-budat MODIF ID cc2.
SELECTION-SCREEN END OF BLOCK b02.


*----------------------------------------------------------------------*
* CLASS DEFINITION
*----------------------------------------------------------------------*
CLASS lcl_main DEFINITION.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_wbs_data,
             psphi TYPE prps-psphi,    "Project Definition
             posid TYPE prps-posid,    "WBS Element
             pspnr TYPE prps-pspnr,    "WBS Element
             post1 TYPE prps-post1,    "Description
             objnr TYPE prps-objnr,    "Object Number
           END OF ty_wbs_data.

    TYPES: BEGIN OF ty_wbs_settlement_rule,
             psphi        TYPE prps-psphi,    "Project Definition
*             posid_hkcg   TYPE prps-posid,    "HKCG WBS Element
             posid        TYPE prps-posid,    "AIIL WBS Element
             post1        TYPE prps-post1,    "Description
             lfdnr        TYPE cobrb-lfdnr,   "Sequence Number
             perbz        TYPE cobrb-perbz,   "Settlement Type
             urzuo        TYPE cobrb-urzuo,   "Source Assignment
             prozs        TYPE cobrb-prozs,   "Percentage
             konty        TYPE cobrb-konty,   "Category
             hkont        TYPE cobrb-hkont,   "G/L Account
             kostl        TYPE cobrb-kostl,   "Cost Center
             message      TYPE string,        "Message
             message_type TYPE icon_d,       "Message Type Icon
           END OF ty_wbs_settlement_rule.

    TYPES: BEGIN OF ty_order_data,
             pspnr        TYPE prps-pspnr,    "AIIL WBS
             aufnr        TYPE coas-aufnr,    "AIIL Order
             lfdnr        TYPE cobrb-lfdnr,   "Sequence Number
             perbz        TYPE cobrb-perbz,   "Settlement Type
             urzuo        TYPE cobrb-urzuo,   "Source Assignment
             prozs        TYPE cobrb-prozs,   "Percentage
             konty        TYPE cobrb-konty,   "Category
             hkont        TYPE cobrb-hkont,   "G/L Account
             kostl        TYPE cobrb-kostl,   "Cost Center
             message      TYPE string,        "Message
             message_type TYPE icon_d,       "Message Type Icon
           END OF ty_order_data.

    TYPES: tt_wbs_data            TYPE TABLE OF ty_wbs_data WITH EMPTY KEY,
           tt_wbs_settlement_rule TYPE TABLE OF ty_wbs_settlement_rule WITH EMPTY KEY,
           tt_order_data          TYPE TABLE OF ty_order_data WITH EMPTY KEY.

    METHODS:
      constructor,
      main_processing,
*      create_settlement_rules
*        CHANGING ct_settlement_rules TYPE tt_settlement_rule,
*      modify_internal_orders
*        CHANGING ct_order_data TYPE tt_order_data,
*      transfer_cost_revenue,
      display_alv
        IMPORTING iv_title TYPE string OPTIONAL
        CHANGING  it_data  TYPE ANY TABLE.
*      create_log
*        RETURNING VALUE(rv_log_handle) TYPE balloghndl,
*      add_message_to_log
*        IMPORTING iv_message  TYPE string
*                  iv_msg_type TYPE symsgty DEFAULT 'I',
*      display_log.

  PRIVATE SECTION.
    DATA mv_log_handle TYPE balloghndl.
    DATA mt_wbs_data            TYPE tt_wbs_data.
    DATA mt_wbs_settlement_rules    TYPE tt_wbs_settlement_rule.
    DATA mt_order_data          TYPE tt_order_data.
    DATA mr_salv_table TYPE REF TO cl_salv_table.

    CONSTANTS: c_company_hkcg    TYPE bukrs VALUE 'HKCG',
               c_company_aiil    TYPE bukrs VALUE 'AIIL',
               c_appliance       TYPE prps-post1 VALUE 'APPLIANCE',
               c_carcassing      TYPE prps-post1 VALUE 'CARCASSING',
               c_kitchen_cabinet TYPE prps-post1 VALUE 'KITCHEN CABINET'.

    METHODS:
      get_hkcg_wbs_data,
      prepare_aiil_wbs_settl_rule,
*      conversion_exit_abpsp_output
*        IMPORTING iv_pspnr        TYPE ps_posnr
*        RETURNING VALUE(rv_pspnr) TYPE ps_posnr,
      conversion_exit_abpsp_input
        IMPORTING iv_posid        TYPE ps_posid
        RETURNING VALUE(rv_pspnr) TYPE ps_posnr,
*      conversion_exit_abpsn_output
*        IMPORTING iv_posid        TYPE ps_posid
*        RETURNING VALUE(rv_posid) TYPE ps_posid,
      get_aiil_wbs_naming
        IMPORTING iv_hkcg_wbs        TYPE ps_posid
        RETURNING VALUE(rv_aiil_wbs) TYPE ps_posid,
      copy_wbs_to_aiil
        IMPORTING is_hkcg_wbs        TYPE bapi_bus2054_detail
        RETURNING VALUE(rs_aiil_wbs) TYPE bapi_bus2054_new.
*    get_settlement_rule_template
*      RETURNING VALUE(rt_settlement_template) TYPE tt_settlement_rule,
*      check_wbs_status
*        IMPORTING iv_wbs_element     TYPE prps-pspnr
*        RETURNING VALUE(rv_is_valid) TYPE abap_bool.
ENDCLASS.


AT SELECTION-SCREEN OUTPUT.
  " Modify selection screen based on selected options
  LOOP AT SCREEN.
    IF p_opt1 = 'X' OR p_opt2 = 'X'.
      " Show Cost Center, hide Posting Date
      IF screen-group1 = 'CC1'.
        screen-active = 1.
      ELSEIF screen-group1 = 'CC2'.
        screen-active = 0.
      ENDIF.
    ELSEIF p_opt3 = 'X'.
      " Hide Cost Center, show Posting Date
      IF screen-group1 = 'CC1'.
        screen-active = 0.
      ELSEIF screen-group1 = 'CC2'.
        screen-active = 1.
      ENDIF.
    ENDIF.
    MODIFY SCREEN.
  ENDLOOP.

AT SELECTION-SCREEN.
  " Validate selection screen inputs
  IF p_opt1 = 'X' OR p_opt2 = 'X'.
    IF p_kostl IS INITIAL.
      MESSAGE 'Cost Center is required.' TYPE 'E'.
    ENDIF.
  ENDIF.

START-OF-SELECTION.
  DATA: lo_main TYPE REF TO lcl_main.

  " Create main object and process
  CREATE OBJECT lo_main.
  lo_main->main_processing( ).


*----------------------------------------------------------------------*
* CLASS IMPLEMENTATION
*----------------------------------------------------------------------*
CLASS lcl_main IMPLEMENTATION.
  METHOD constructor.
    " Initialize and create application log
*    mv_log_handle = create_log( ).
  ENDMETHOD.


  METHOD main_processing.
    " Get HKCG WBS data
    get_hkcg_wbs_data( ).

    " Process based on selected option
    CASE 'X'.
      WHEN p_opt1.
        " Prepare AIIL WBS Elements and Settlement Rule
        prepare_aiil_wbs_settl_rule( ).
*
*        " Prepare settlement rules for each WBS
*        LOOP AT gt_wbs_data INTO DATA(ls_wbs).
*          DATA: lt_template TYPE tt_settlement_rule.
*          lt_template = get_settlement_rule_template( ).
*
*          LOOP AT lt_template INTO DATA(ls_template).
*            DATA: ls_settlement TYPE ty_settlement_rule.
*            ls_settlement = ls_template.
*            ls_settlement-pspnr = get_wbs_naming_rule( ls_wbs-pspnr ).
*            ls_settlement-post1 = ls_wbs-post1.
*            ls_settlement-kostl = p_kostl.
*            APPEND ls_settlement TO gt_settlement_rules.
*          ENDLOOP.
*        ENDLOOP.
*
*        create_settlement_rules( CHANGING ct_settlement_rules = gt_settlement_rules ).

*      WHEN p_opt2.
*        " Option 2: Modify AIIL Internal Orders
*        LOOP AT gt_wbs_data INTO ls_wbs.
*          DATA: lt_template_order TYPE tt_settlement_rule.
*          lt_template_order = get_settlement_rule_template( ).
*
*          LOOP AT lt_template_order INTO DATA(ls_template_order).
*            DATA: ls_order TYPE ty_order_data.
*            ls_order-pspnr = get_wbs_naming_rule( ls_wbs-pspnr ).
*            ls_order-lfdnr = ls_template_order-lfdnr.
*            ls_order-perbz = ls_template_order-perbz.
*            ls_order-urzuo = ls_template_order-urzuo.
*            ls_order-prozs = ls_template_order-prozs.
*            ls_order-konty = ls_template_order-konty.
*            ls_order-hkont = ls_template_order-hkont.
*            ls_order-kostl = p_kostl.
*            APPEND ls_order TO gt_order_data.
*          ENDLOOP.
*        ENDLOOP.
*
*        modify_internal_orders( CHANGING ct_order_data = gt_order_data ).
*
*      WHEN p_opt3.
*        " Option 3: Transfer Cost and Revenue
*        transfer_cost_revenue( ).
    ENDCASE.

    display_alv( CHANGING it_data = mt_wbs_settlement_rules ).
  ENDMETHOD.

  METHOD get_hkcg_wbs_data.

    " Get HKCG WBS data using BAPI_BUS2054_GETDATA
    SELECT pspnr, posid, post1, objnr, psphi
      FROM prps
      INTO CORRESPONDING FIELDS OF TABLE @mt_wbs_data
      WHERE posid IN @s_wbs
        AND erdat IN @s_erdat
        AND pbukr = @c_company_hkcg
        AND ( post1 = @c_appliance OR
              post1 = @c_carcassing OR
              post1 = @c_kitchen_cabinet ).

    IF mt_wbs_data[] IS NOT INITIAL.
      SELECT *
        INTO TABLE @DATA(lt_jest)
        FROM jest
        FOR ALL ENTRIES IN @mt_wbs_data
       WHERE objnr = @mt_wbs_data-objnr
         AND stat  = 'I0046' "Closed
         AND inact = ''.
      SORT lt_jest BY objnr.
    ENDIF.

    LOOP AT mt_wbs_data ASSIGNING FIELD-SYMBOL(<fs_wbs_data>).
      DATA(lv_tabix) = sy-tabix.
      READ TABLE lt_jest TRANSPORTING NO FIELDS
        WITH KEY objnr = <fs_wbs_data>-objnr BINARY SEARCH.
      IF sy-subrc = 0.
        DELETE mt_wbs_data INDEX lv_tabix.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD prepare_aiil_wbs_settl_rule.

    DATA lv_wbs_aiil TYPE ps_posid.
    DATA lv_pspnr TYPE ps_posnr.
    DATA lt_cobrb TYPE TABLE OF cobrb WITH EMPTY KEY.

    SORT mt_wbs_data BY psphi posid.

    LOOP AT mt_wbs_data ASSIGNING FIELD-SYMBOL(<fs_wbs_data>).
      CLEAR: lv_wbs_aiil, lv_pspnr.
      lv_wbs_aiil = get_aiil_wbs_naming( <fs_wbs_data>-posid ).
      lv_pspnr = conversion_exit_abpsp_input( lv_wbs_aiil ).

      IF lv_pspnr IS NOT INITIAL.  "WBS Element exists
        CONTINUE.
      ENDIF.

      SELECT objnr lfdnr perbz urzuo prozs konty hkont
        INTO CORRESPONDING FIELDS OF TABLE lt_cobrb
        FROM cobrb
       WHERE objnr = <fs_wbs_data>-objnr.

      LOOP AT lt_cobrb ASSIGNING FIELD-SYMBOL(<fs_cobrb>).
        APPEND INITIAL LINE TO mt_wbs_settlement_rules ASSIGNING FIELD-SYMBOL(<fs_wbs_rule>).
        MOVE-CORRESPONDING <fs_cobrb> TO <fs_wbs_rule>.
        <fs_wbs_rule>-psphi = <fs_wbs_data>-psphi.
        <fs_wbs_rule>-post1 = <fs_wbs_data>-post1.
      ENDLOOP.
    ENDLOOP.

  ENDMETHOD.

*  METHOD create_aiil_wbs_elements.
*    DATA lv_wbs_hkcg TYPE char24.
*    DATA lv_aiil_hkcg TYPE char24.
*    DATA it_wbs_element TYPE TABLE OF bapi_wbs_list.
*    DATA et_wbs_element TYPE TABLE OF bapi_bus2054_detail.
*    DATA et_return TYPE TABLE OF bapiret2.
*    DATA lv_aiil_pspnr TYPE ps_posnr.
*    DATA it_wbs_aiil TYPE TABLE OF bapi_bus2054_new.
*
*    SORT mt_wbs_data BY psphi posid.
*
*    LOOP AT mt_wbs_data ASSIGNING FIELD-SYMBOL(<fs_wbs_data>).
**      AT NEW psphi.
**      ENDAT.
*
*      CLEAR: it_wbs_element, et_wbs_element, et_return.
*
*
*      lv_wbs_hkcg = conversion_exit_abpsp_output( <fs_wbs_data>-pspnr ).
*      lv_aiil_hkcg = get_aiil_wbs_naming( lv_wbs_hkcg ).
*      lv_aiil_pspnr = conversion_exit_abpsp_input( lv_aiil_hkcg ).
*
*      IF lv_aiil_pspnr IS INITIAL.  "WBS Element not exist
*        it_wbs_element = VALUE #( BASE it_wbs_element ( wbs_element = <fs_wbs_data>-posid ) ).
*      ENDIF.
*
*      CHECK it_wbs_element[] IS NOT INITIAL.
*      CALL FUNCTION 'BAPI_PS_INITIALIZATION'.
*
*      CALL FUNCTION 'BAPI_BUS2054_GETDATA'
*        TABLES
*          it_wbs_element = it_wbs_element
*          et_wbs_element = et_wbs_element
*          et_return      = et_return.
*
*      IF et_wbs_element[] IS NOT INITIAL.
*        CLEAR et_return.
*        DATA(ls_hkcg_wbs) = et_wbs_element[ 1 ].
*        DATA(ls_aiil_wbs) = copy_wbs_to_aiil( ls_hkcg_wbs ).
*
*        APPEND ls_aiil_wbs TO it_wbs_aiil.
*        CALL FUNCTION 'BAPI_BUS2054_CREATE_MULTI'
*          EXPORTING
*            i_project_definition = <fs_wbs_data>
*          TABLES
*            it_wbs_element       = it_wbs_aiil
*            et_return            = et_return.
*      ENDIF.
*
*
*
**      AT END OF psphi.
**      ENDAT.
*    ENDLOOP.
*
*  ENDMETHOD.

*  METHOD conversion_exit_abpsp_output.
*
*    CALL FUNCTION 'CONVERSION_EXIT_ABPSP_OUTPUT'
*      EXPORTING
*        input  = iv_pspnr
*      IMPORTING
*        output = rv_pspnr.
*
*  ENDMETHOD.

  METHOD conversion_exit_abpsp_input.

    CALL FUNCTION 'CONVERSION_EXIT_ABPSP_INPUT'
      EXPORTING
        input     = iv_posid
      IMPORTING
        output    = rv_pspnr
      EXCEPTIONS
        not_found = 1
        OTHERS    = 2.
    IF sy-subrc <> 0.
* Implement suitable error handling here
    ENDIF.

  ENDMETHOD.

*  METHOD conversion_exit_abpsn_output.
*
*    CALL FUNCTION 'CONVERSION_EXIT_ABPSN_OUTPUT'
*      EXPORTING
*        input  = iv_posid
*      IMPORTING
*        output = rv_posid.
*
*  ENDMETHOD.

  METHOD get_aiil_wbs_naming.
    DATA: lv_length TYPE i,
          lv_prefix TYPE string,
          lv_suffix TYPE char1.

    lv_length = strlen( iv_hkcg_wbs ).
    lv_length = lv_length - 1.
    lv_prefix = iv_hkcg_wbs+0(lv_length).
    lv_suffix = iv_hkcg_wbs+lv_length(1).

    " Apply naming rules based on specification
    CASE lv_suffix.
      WHEN 'A'.  " Appliance -> X
        rv_aiil_wbs = |{ lv_prefix }X|.
      WHEN 'G'.  " Carcassing -> Y
        rv_aiil_wbs = |{ lv_prefix }Y|.
      WHEN 'K'.  " Kitchen Cabinet -> Z
        rv_aiil_wbs = |{ lv_prefix }Z|.
      WHEN OTHERS.
        rv_aiil_wbs = iv_hkcg_wbs.
    ENDCASE.
  ENDMETHOD.

  METHOD copy_wbs_to_aiil.
    MOVE-CORRESPONDING is_hkcg_wbs TO rs_aiil_wbs.
    rs_aiil_wbs-company_code = c_company_aiil.
  ENDMETHOD.

  METHOD display_alv.
    DATA: lr_columns         TYPE REF TO cl_salv_columns_table,
          lr_display         TYPE REF TO cl_salv_display_settings,
          lv_title           TYPE lvc_title,
          lv_report          TYPE sycprog,
          lv_pfstatus        TYPE sypfkey,
          lv_stext           TYPE scrtext_s,
          lv_ltext           TYPE scrtext_l,
          lr_selections      TYPE REF TO cl_salv_selections,
          lr_layout_settings TYPE REF TO cl_salv_layout,
          ls_layout_key      TYPE salv_s_layout_key,
          lr_events          TYPE REF TO cl_salv_events_table.

    DEFINE set_column_position.
      lr_columns->set_column_position( columnname = &1
                                       position   = &2 ).
    END-OF-DEFINITION.

    IF 1 = 2.
      lv_report = sy-repid.
      lv_pfstatus = 'DEL_STATUS'.
    ELSE.
      lv_report = 'SAPLSALV'.
      lv_pfstatus = 'STANDARD'.
    ENDIF.

* Create an ALV table
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = mr_salv_table
          CHANGING
            t_table      = it_data ).

        mr_salv_table->set_screen_status(
          pfstatus      =  lv_pfstatus
          report        =  lv_report
          set_functions =  mr_salv_table->c_functions_all ).

        lr_columns = mr_salv_table->get_columns( ).
* optimize columns' width
        lr_columns->set_optimize( value = abap_true ).
* fix key columns
        lr_columns->set_key_fixation( value = abap_true ).

* Set selection mode
        lr_selections = mr_salv_table->get_selections( ).
        lr_selections->set_selection_mode( if_salv_c_selection_mode=>row_column ).

        lr_layout_settings = mr_salv_table->get_layout( ).
        ls_layout_key-report = sy-repid.
        lr_layout_settings->set_key( ls_layout_key ).
        lr_layout_settings->set_save_restriction( if_salv_c_layout=>restrict_none ).

* Display the table
        mr_salv_table->display( ).
      CATCH cx_root INTO DATA(lx_root).
        MESSAGE lx_root->get_text( ) TYPE 'E'.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.
