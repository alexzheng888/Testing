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
  SELECT-OPTIONS: s_proj   FOR prps-psphi OBLIGATORY MATCHCODE OBJECT prsm,
                  s_wbs    FOR prps-posid MATCHCODE OBJECT prpm,
                  s_erdat  FOR prps-erdat.
  PARAMETERS:     p_kostl  TYPE cobrb-kostl OBLIGATORY MATCHCODE OBJECT kost.
SELECTION-SCREEN END OF BLOCK b01.


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
             message_type TYPE icon_d,       "Message Type Icon
             message      TYPE bapi_msg,        "Message
             posid_hkcg   TYPE prps-posid,    "HKCG WBS Element
             objnr_hkcg   TYPE prps-objnr,    "HKCG Object Number
             executed     TYPE char1,
           END OF ty_wbs_settlement_rule.


    TYPES: tt_wbs_data            TYPE TABLE OF ty_wbs_data WITH EMPTY KEY,
           tt_wbs_settlement_rule TYPE TABLE OF ty_wbs_settlement_rule WITH EMPTY KEY.

    METHODS:
      constructor,
      main_processing.

  PRIVATE SECTION.
    DATA mv_log_handle TYPE balloghndl.
    DATA mt_wbs_data            TYPE tt_wbs_data.
    DATA mt_wbs_settlement_rules    TYPE tt_wbs_settlement_rule.
    DATA mr_salv_table TYPE REF TO cl_salv_table.
    DATA mt_bdcdata TYPE TABLE OF bdcdata.
    DATA mt_messtab TYPE TABLE OF bdcmsgcoll.

    CONSTANTS: c_company_hkcg    TYPE bukrs VALUE 'HKCG',
               c_company_aiil    TYPE bukrs VALUE 'AIIL',
               c_appliance       TYPE prps-post1 VALUE 'APPLIANCE',
               c_carcassing      TYPE prps-post1 VALUE 'CARCASSING',
               c_kitchen_cabinet TYPE prps-post1 VALUE 'KITCHEN CABINET',
               c_icon_green      TYPE icon_d VALUE '@08@',
               c_icon_red        TYPE icon_d VALUE '@0A@',
               c_icon_yellow     TYPE icon_d VALUE '@09@'.
    METHODS:
      get_hkcg_wbs_data,
      prepare_aiil_wbs_settl_rule,
      create_aiil_wbs_settl_rule,
      call_cj02_bdc
        IMPORTING is_wbs_settl_rule TYPE ty_wbs_settlement_rule
        RETURNING VALUE(cv_message) TYPE string,
      bdc_dynpro
        IMPORTING program TYPE bdc_prog
                  dynpro  TYPE bdc_dynr,
      bdc_field
        IMPORTING fnam TYPE fnam_____4
                  fval TYPE bdc_fval,
      conversion_exit_abpsp_input
        IMPORTING iv_posid        TYPE ps_posid
        RETURNING VALUE(rv_pspnr) TYPE ps_posnr,
      conversion_exit_abpsn_output
        IMPORTING iv_posid        TYPE ps_posid
        RETURNING VALUE(rv_posid) TYPE ps_posid,
      conversion_exit_obart_output
        IMPORTING iv_konty        TYPE konty
        RETURNING VALUE(rv_konty) TYPE char10,
      conversion_exit_perbz_output
        IMPORTING iv_perbz        TYPE perbz_ld
        RETURNING VALUE(rv_perbz) TYPE char10,
      get_aiil_wbs_naming
        IMPORTING iv_hkcg_wbs        TYPE ps_posid
        RETURNING VALUE(rv_aiil_wbs) TYPE ps_posid,
      copy_wbs_to_aiil
        IMPORTING is_hkcg_wbs        TYPE bapi_bus2054_detail
        RETURNING VALUE(rs_aiil_wbs) TYPE bapi_bus2054_new,
      display_alv
        IMPORTING iv_title TYPE string OPTIONAL
        CHANGING  it_data  TYPE ANY TABLE,
      on_user_command FOR EVENT added_function OF cl_salv_events
        IMPORTING e_salv_function.
ENDCLASS.


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
  ENDMETHOD.


  METHOD main_processing.
    " Get HKCG WBS data
    get_hkcg_wbs_data( ).

    " Prepare AIIL WBS Elements and Settlement Rule
    prepare_aiil_wbs_settl_rule( ).

    display_alv( CHANGING it_data = mt_wbs_settlement_rules ).
  ENDMETHOD.

  METHOD get_hkcg_wbs_data.

    " Get HKCG WBS data using BAPI_BUS2054_GETDATA
    SELECT pspnr, posid, post1, objnr, psphi
      FROM prps
      INTO CORRESPONDING FIELDS OF TABLE @mt_wbs_data
      WHERE posid IN @s_wbs
        AND psphi IN @s_proj
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
      SORT lt_cobrb BY objnr lfdnr.

      LOOP AT lt_cobrb ASSIGNING FIELD-SYMBOL(<fs_cobrb>).
        APPEND INITIAL LINE TO mt_wbs_settlement_rules ASSIGNING FIELD-SYMBOL(<fs_wbs_rule>).
        MOVE-CORRESPONDING <fs_cobrb> TO <fs_wbs_rule>.
        <fs_wbs_rule>-psphi = <fs_wbs_data>-psphi.
        <fs_wbs_rule>-posid = lv_wbs_aiil.
        <fs_wbs_rule>-post1 = <fs_wbs_data>-post1.
        <fs_wbs_rule>-kostl = p_kostl.
        <fs_wbs_rule>-posid_hkcg = <fs_wbs_data>-posid.
        <fs_wbs_rule>-objnr_hkcg = <fs_wbs_data>-objnr.
      ENDLOOP.
    ENDLOOP.

  ENDMETHOD.

  METHOD create_aiil_wbs_settl_rule.

    DATA it_wbs_element TYPE TABLE OF bapi_wbs_list.
    DATA et_wbs_element TYPE TABLE OF bapi_bus2054_detail.
    DATA ls_wbs_element TYPE bapi_bus2054_detail.
    DATA et_return TYPE TABLE OF bapiret2.
    DATA it_wbs_aiil TYPE TABLE OF bapi_bus2054_new.
    DATA ls_wbs_aiil TYPE bapi_bus2054_new.
    DATA lv_msg TYPE string.
    DATA lv_text TYPE string.
    DATA lv_posid TYPE prps-posid.

    LOOP AT mt_wbs_settlement_rules ASSIGNING FIELD-SYMBOL(<fs_wbs_rule>).
      CHECK <fs_wbs_rule>-executed IS INITIAL.

      AT NEW posid.
        lv_posid = conversion_exit_abpsn_output( <fs_wbs_rule>-posid ).
        lv_text = |Processing WBS { lv_posid } ...|.
        CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
          EXPORTING
            text = lv_text.

        CLEAR: it_wbs_element, et_wbs_element, et_return, lv_msg.

        it_wbs_element = VALUE #( ( wbs_element = <fs_wbs_rule>-posid_hkcg ) ).
        CALL FUNCTION 'BAPI_BUS2054_GETDATA'
          TABLES
            it_wbs_element = it_wbs_element
            et_wbs_element = et_wbs_element
            et_return      = et_return.

        IF et_wbs_element IS INITIAL.
          LOOP AT et_return ASSIGNING FIELD-SYMBOL(<fs_return>)
                            WHERE type CA 'EAX'.
            CONCATENATE lv_msg <fs_return>-message INTO lv_msg SEPARATED BY space.
          ENDLOOP.
          CONDENSE lv_msg.
        ELSE.
          CLEAR: ls_wbs_element, ls_wbs_aiil, it_wbs_aiil, et_return.

          ls_wbs_element = et_wbs_element[ 1 ].
          ls_wbs_aiil = copy_wbs_to_aiil( ls_wbs_element ).
          ls_wbs_aiil-wbs_element = <fs_wbs_rule>-posid.
          APPEND ls_wbs_aiil TO it_wbs_aiil.

          CALL FUNCTION 'BAPI_PS_INITIALIZATION'.

          CALL FUNCTION 'BAPI_BUS2054_CREATE_MULTI'
            EXPORTING
              i_project_definition = ls_wbs_element-project_definition
            TABLES
              it_wbs_element       = it_wbs_aiil
              et_return            = et_return.

          DELETE et_return WHERE type NA 'EAX'.
          IF et_return IS NOT INITIAL.
            LOOP AT et_return ASSIGNING <fs_return>.
              CONCATENATE lv_msg <fs_return>-message INTO lv_msg SEPARATED BY space.
            ENDLOOP.
            CONDENSE lv_msg.

            CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
          ELSE.
            CLEAR et_return.
            CALL FUNCTION 'BAPI_PS_PRECOMMIT'
              TABLES
                et_return = et_return.

            DELETE et_return WHERE type NA 'EAX'.
            IF et_return IS NOT INITIAL.
              LOOP AT et_return ASSIGNING <fs_return>.
                CONCATENATE lv_msg <fs_return>-message INTO lv_msg SEPARATED BY space.
              ENDLOOP.
              CONDENSE lv_msg.

              CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
            ELSE.
              CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
                EXPORTING
                  wait = 'X'.
              <fs_wbs_rule>-executed = 'X'.
              lv_msg = call_cj02_bdc( <fs_wbs_rule> ).
            ENDIF.
          ENDIF.
        ENDIF.
      ENDAT.

      IF lv_msg IS NOT INITIAL.
        <fs_wbs_rule>-message_type = c_icon_red.
        <fs_wbs_rule>-message = lv_msg.
      ELSE.
        <fs_wbs_rule>-message_type = c_icon_green.
        <fs_wbs_rule>-message = 'Settlement rules created successfully'.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD call_cj02_bdc.

    DATA ls_opt TYPE ctu_params.
    DATA lv_index TYPE numc2.
    DATA lv_message TYPE string.
    DATA lv_fval TYPE bdc_fval.

    CLEAR: mt_bdcdata, mt_messtab.

    bdc_dynpro( program = 'SAPLCJWB' dynpro = '0100' ).
*    bdc_field( fnam = 'BDC_CURSOR' fval = '*PRPS-POSID' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '=LETB' ).
    bdc_field( fnam = '*PRPS-POSID' fval = CONV #( is_wbs_settl_rule-posid ) ).

    bdc_dynpro( program = 'SAPLCJWB' dynpro = '0901' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '=ABRV' ).
*    bdc_field( fnam = 'BDC_SUBSCR' fval = 'SAPLCJWB                                0902LISTE' ).
    bdc_field( fnam = 'BDC_CURSOR' fval = 'PRPS-STUFE(01)' ).
    bdc_field( fnam = 'RCJ_MARKL-MARK(01)' fval = 'X' ).
*    bdc_field( fnam = 'BDC_SUBSCR' fval = 'SAPLCJWB                                3993BUTTONS' ).

    LOOP AT mt_wbs_settlement_rules ASSIGNING FIELD-SYMBOL(<fs_settl_rule>)
                                    WHERE psphi = is_wbs_settl_rule-psphi
                                      AND posid = is_wbs_settl_rule-posid.
      lv_index = sy-tabix.
      bdc_dynpro( program = 'SAPLKOBS' dynpro = '0130' ).
*      bdc_field( fnam = 'BDC_CURSOR' fval = 'COBRB-KONTY(01)' ).
      bdc_field( fnam = 'BDC_OKCODE' fval = '=DETA' ).
      lv_fval = conversion_exit_obart_output( <fs_settl_rule>-konty ).
      CONDENSE lv_fval.
      bdc_field( fnam = |COBRB-KONTY({ lv_index })| fval = lv_fval ).
      bdc_field( fnam = |DKOBR-EMPGE({ lv_index })| fval = CONV #( <fs_settl_rule>-hkont ) ).
      lv_fval = CONV #( <fs_settl_rule>-prozs ).
      CONDENSE lv_fval.
      bdc_field( fnam = |COBRB-PROZS({ lv_index })| fval = lv_fval ).
      lv_fval = conversion_exit_perbz_output( <fs_settl_rule>-perbz ).
      CONDENSE lv_fval.
      bdc_field( fnam = |COBRB-PERBZ({ lv_index })| fval = lv_fval ).
      bdc_field( fnam = |COBRB-URZUO({ lv_index })| fval = CONV #( <fs_settl_rule>-urzuo ) ).
      bdc_field( fnam = |COBRB-EXTNR({ lv_index })| fval = CONV #( <fs_settl_rule>-lfdnr ) ).
*      bdc_field( fnam = 'BDC_SUBSCR' fval = 'SAPLKOBS                                0205BLOCK1' ).

      bdc_dynpro( program = 'SAPLKOBS' dynpro = '0100' ).
      bdc_field( fnam = 'BDC_OKCODE' fval = '=BACK' ).
      bdc_field( fnam = 'COBL-KOSTL' fval = CONV #( <fs_settl_rule>-kostl ) ).
    ENDLOOP.

    " Final save and exit
    bdc_dynpro( program = 'SAPLKOBS' dynpro = '0130' ).
*    bdc_field( fnam = 'BDC_CURSOR' fval = 'COBRB-KONTY(01)' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '/00' ).
*    bdc_field( fnam = 'BDC_SUBSCR' fval = 'SAPLKOBS                                0205BLOCK1' ).

    bdc_dynpro( program = 'SAPLKOBS' dynpro = '0130' ).
*    bdc_field( fnam = 'BDC_CURSOR' fval = 'COBRB-KONTY(01)' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '=BACK' ).
*    bdc_field( fnam = 'BDC_SUBSCR' fval = 'SAPLKOBS                                0205BLOCK1' ).

    bdc_dynpro( program = 'SAPLCJWB' dynpro = '0901' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '=BU' ).
*    bdc_field( fnam = 'BDC_SUBSCR' fval = 'SAPLCJWB                                0902LISTE' ).
*    bdc_field( fnam = 'BDC_CURSOR' fval = 'PRPS-STUFE(01)' ).
*    bdc_field( fnam = 'BDC_SUBSCR' fval = 'SAPLCJWB                                3993BUTTONS' ).

    " Execute BDC transaction
    ls_opt-dismode = 'N'.
    ls_opt-updmode = 'S'.
    ls_opt-defsize = 'X'.
    ls_opt-racommit = 'X'.

    CALL TRANSACTION 'CJ02' USING mt_bdcdata
                            OPTIONS FROM ls_opt
                            MESSAGES INTO mt_messtab.

    DELETE mt_messtab WHERE msgtyp NA 'EAX'.
    IF mt_messtab IS NOT INITIAL.
      " Error occurred
      LOOP AT mt_messtab ASSIGNING FIELD-SYMBOL(<fs_msg>).
        MESSAGE ID <fs_msg>-msgid TYPE <fs_msg>-msgtyp NUMBER <fs_msg>-msgnr
                WITH <fs_msg>-msgv1 <fs_msg>-msgv2 <fs_msg>-msgv3 <fs_msg>-msgv4 INTO lv_message.
        CONCATENATE cv_message lv_message
                   INTO cv_message SEPARATED BY space.
      ENDLOOP.
      CONDENSE cv_message.
    ENDIF.

  ENDMETHOD.

  METHOD bdc_dynpro.

    APPEND INITIAL LINE TO mt_bdcdata ASSIGNING FIELD-SYMBOL(<fs_bdcdata>).
    <fs_bdcdata>-program  = program.
    <fs_bdcdata>-dynpro   = dynpro.
    <fs_bdcdata>-dynbegin = 'X'.

  ENDMETHOD.

  METHOD bdc_field.

    CHECK fval IS NOT INITIAL.
    APPEND INITIAL LINE TO mt_bdcdata ASSIGNING FIELD-SYMBOL(<fs_bdcdata>).
    <fs_bdcdata>-fnam  = fnam.
    <fs_bdcdata>-fval  = fval.
*    CONDENSE <fs_bdcdata>-fval.

  ENDMETHOD.

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

  METHOD conversion_exit_abpsn_output.

    CALL FUNCTION 'CONVERSION_EXIT_ABPSN_OUTPUT'
      EXPORTING
        input  = iv_posid
      IMPORTING
        output = rv_posid.

  ENDMETHOD.

  METHOD conversion_exit_obart_output.

    CALL FUNCTION 'CONVERSION_EXIT_OBART_OUTPUT'
      EXPORTING
        input  = iv_konty
      IMPORTING
        output = rv_konty.

  ENDMETHOD.

  METHOD conversion_exit_perbz_output.

    CALL FUNCTION 'CONVERSION_EXIT_PERBZ_OUTPUT'
      EXPORTING
        input  = iv_perbz
      IMPORTING
        output = rv_perbz.

  ENDMETHOD.

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
    rs_aiil_wbs-plant = c_company_aiil.
    CLEAR: rs_aiil_wbs-wbs_up, rs_aiil_wbs-wbs_left.
  ENDMETHOD.

  METHOD display_alv.
    DATA: lr_columns         TYPE REF TO cl_salv_columns_table,
          lr_column          TYPE REF TO cl_salv_column_table,
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

    lv_report = sy-repid.
    lv_pfstatus = 'STANDARD'.

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

        lr_columns->get_column( 'PSPHI' )->set_technical( ).
        lr_columns->get_column( 'POSID_HKCG' )->set_technical( ).
        lr_columns->get_column( 'OBJNR_HKCG' )->set_technical( ).
        lr_columns->get_column( 'EXECUTED' )->set_technical( ).

        lr_columns->get_column( 'PROZS' )->set_long_text( 'Percent %' ).

        lr_column ?= lr_columns->get_column( 'MESSAGE_TYPE' ).
        lr_column->set_icon( ).
        lr_column->set_long_text( 'Status' ).

* Set selection mode
        lr_selections = mr_salv_table->get_selections( ).
        lr_selections->set_selection_mode( if_salv_c_selection_mode=>row_column ).

        lr_layout_settings = mr_salv_table->get_layout( ).
        ls_layout_key-report = sy-repid.
        lr_layout_settings->set_key( ls_layout_key ).
        lr_layout_settings->set_save_restriction( if_salv_c_layout=>restrict_none ).

        lr_events = mr_salv_table->get_event( ).
        SET HANDLER on_user_command FOR lr_events.

* Display the table
        mr_salv_table->display( ).
      CATCH cx_root INTO DATA(lx_root).
        MESSAGE lx_root->get_text( ) TYPE 'E'.
    ENDTRY.

  ENDMETHOD.

  METHOD on_user_command.
    DATA lv_question TYPE string.
    DATA lv_answer TYPE char1.

    CASE e_salv_function.
      WHEN '&ZSAVE'.
        lv_question = `Create all the WBS elements and settlement rules in bulk?`.
        CALL FUNCTION 'POPUP_TO_CONFIRM'
          EXPORTING
            titlebar              = 'Please confirm the action'
            text_question         = lv_question
            text_button_1         = 'Yes'
            text_button_2         = 'No'
            default_button        = '2'
            display_cancel_button = ''
          IMPORTING
            answer                = lv_answer
          EXCEPTIONS
            text_not_found        = 1
            OTHERS                = 2.
        IF lv_answer <> '1'.
          EXIT.
        ENDIF.

        create_aiil_wbs_settl_rule( ).

        mr_salv_table->get_columns( )->set_optimize( ).
        mr_salv_table->refresh( ).
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
