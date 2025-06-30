*&---------------------------------------------------------------------*
*& Program Name     : ZPRRP019                                         *
*& Title            : Mass Change AIIL Internal Order Settlement Rule  *
*& Module Name      : CO                                               *
*& Author           : Alex Zheng                                       *
*& Create Date      : 30.06.2025                                       *
*& Logical DB       : None                                             *
*& Program Type     : Report                                           *
*&---------------------------------------------------------------------*
*& MODIFICATION LOG                                                    *
*&                                                                     *
*& LOG#  DATE        AUTHOR        DESCRIPTION                         *
*& ----  ----        ------        -----------                         *
*& 0000  30.06.2025  Dynasys       Initial Implementation              *
*&---------------------------------------------------------------------*
REPORT zprrp019.

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

    TYPES: BEGIN OF ty_interal_order,
             psphi        TYPE prps-psphi,    "Project Definition
             posid        TYPE prps-posid,    "AIIL WBS Element
             aufnr        TYPE coas-aufnr,    "AIIL Order
             lfdnr        TYPE cobrb-lfdnr,   "Sequence Number
             perbz        TYPE cobrb-perbz,   "Settlement Type
             urzuo        TYPE cobrb-urzuo,   "Source Assignment
             prozs        TYPE cobrb-prozs,   "Percentage
             konty        TYPE cobrb-konty,   "Category
             hkont        TYPE cobrb-hkont,   "G/L Account
             kostl        TYPE cobrb-kostl,   "Cost Center
             message_type TYPE icon_d,       "Message Type Icon
             message      TYPE bapi_msg,        "Message
             objnr_aiil   TYPE aufk-objnr,    "HKCG WBS Element
           END OF ty_interal_order.

    TYPES: tt_wbs_data      TYPE TABLE OF ty_wbs_data WITH EMPTY KEY,
           tt_interal_order TYPE TABLE OF ty_interal_order WITH EMPTY KEY.

    METHODS:
      constructor,
      main_processing.

  PRIVATE SECTION.
    DATA mt_wbs_data      TYPE tt_wbs_data.
    DATA mt_interal_order TYPE tt_interal_order.
    DATA mr_salv_table    TYPE REF TO cl_salv_table.
    DATA mt_bdcdata TYPE TABLE OF bdcdata.
    DATA mt_messtab TYPE TABLE OF bdcmsgcoll.

    CONSTANTS: c_company_hkcg TYPE bukrs VALUE 'HKCG',
               c_company_aiil TYPE bukrs VALUE 'AIIL',
               c_icon_green   TYPE icon_d VALUE '@08@',
               c_icon_red     TYPE icon_d VALUE '@0A@',
               c_icon_yellow  TYPE icon_d VALUE '@09@'.

    METHODS:
      get_hkcg_wbs_data,
      get_aiil_wbs_naming
        IMPORTING iv_hkcg_wbs    TYPE ps_posid
        EXPORTING ev_aiil_wbs    TYPE ps_posid
                  ev_hkcg_suffix TYPE char1,
      prepare_aiil_iorder_rules,
      conversion_exit_abpsp_input
        IMPORTING iv_posid        TYPE ps_posid
        RETURNING VALUE(rv_pspnr) TYPE ps_posnr,
      display_alv
        IMPORTING iv_title TYPE string OPTIONAL
        CHANGING  it_data  TYPE ANY TABLE,
      on_user_command FOR EVENT added_function OF cl_salv_events
        IMPORTING e_salv_function,
      change_iorder_settl_rule,
      call_ko02_bdc
        IMPORTING is_iorder_settl_rule TYPE ty_interal_order
        RETURNING VALUE(cv_message)    TYPE string,
      conversion_exit_obart_output
        IMPORTING iv_konty        TYPE konty
        RETURNING VALUE(rv_konty) TYPE char10,
      conversion_exit_perbz_output
        IMPORTING iv_perbz        TYPE perbz_ld
        RETURNING VALUE(rv_perbz) TYPE char10,
      bdc_dynpro
        IMPORTING program TYPE bdc_prog
                  dynpro  TYPE bdc_dynr,
      bdc_field
        IMPORTING fnam TYPE fnam_____4
                  fval TYPE bdc_fval.

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

    " Prepare AIIL Internal Order and Settlement Rule
    prepare_aiil_iorder_rules( ).

    display_alv( CHANGING it_data = mt_interal_order ).
  ENDMETHOD.


  METHOD get_hkcg_wbs_data.
    DATA lv_suffix TYPE char1.

    SELECT pspnr, posid, post1, objnr, psphi
      FROM prps
      INTO CORRESPONDING FIELDS OF TABLE @mt_wbs_data
      WHERE posid IN @s_wbs
        AND psphi IN @s_proj
        AND erdat IN @s_erdat
        AND pbukr = @c_company_hkcg.

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
      CLEAR: lv_suffix.

      get_aiil_wbs_naming(
        EXPORTING iv_hkcg_wbs = <fs_wbs_data>-posid
        IMPORTING ev_hkcg_suffix = lv_suffix ).

      IF lv_suffix NA 'AGK'.
        DELETE mt_wbs_data INDEX lv_tabix.
        CONTINUE.
      ENDIF.

      READ TABLE lt_jest TRANSPORTING NO FIELDS
        WITH KEY objnr = <fs_wbs_data>-objnr BINARY SEARCH.
      IF sy-subrc = 0.
        DELETE mt_wbs_data INDEX lv_tabix.
        CONTINUE.
      ENDIF.
    ENDLOOP.

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
        ev_aiil_wbs = |{ lv_prefix }X|.
      WHEN 'G'.  " Carcassing -> Y
        ev_aiil_wbs = |{ lv_prefix }Y|.
      WHEN 'K'.  " Kitchen Cabinet -> Z
        ev_aiil_wbs = |{ lv_prefix }Z|.
      WHEN OTHERS.
        ev_aiil_wbs = iv_hkcg_wbs.
    ENDCASE.

    ev_hkcg_suffix = lv_suffix.
  ENDMETHOD.

  METHOD prepare_aiil_iorder_rules.
    DATA lv_wbs_aiil TYPE ps_posid.
    DATA lv_pspnr TYPE ps_posnr.

    SORT mt_wbs_data BY psphi posid.
    LOOP AT mt_wbs_data ASSIGNING FIELD-SYMBOL(<fs_wbs_data>).
      CLEAR: lv_wbs_aiil, lv_pspnr.
      get_aiil_wbs_naming(
        EXPORTING iv_hkcg_wbs = <fs_wbs_data>-posid
        IMPORTING ev_aiil_wbs = lv_wbs_aiil ).

      lv_pspnr = conversion_exit_abpsp_input( lv_wbs_aiil ).
      CHECK lv_pspnr IS NOT INITIAL.

      "Get HKCG Internal Order
      SELECT pspel, aufnr, objnr
        INTO TABLE @DATA(lt_aufk)
        FROM aufk
       WHERE pspel = @<fs_wbs_data>-pspnr.
      SORT lt_aufk BY pspel aufnr.

      LOOP AT lt_aufk ASSIGNING FIELD-SYMBOL(<fs_aufk>).
        DATA(lv_aufnr) = <fs_aufk>-aufnr && 'A'.
        SELECT SINGLE aufnr, objnr
          INTO @DATA(ls_aufk_aiil)
          FROM aufk
         WHERE aufnr = @lv_aufnr.
        IF sy-subrc NE 0.
          CONTINUE.
        ELSE. "AIIL Internal Order existing
          SELECT SINGLE objnr INTO @DATA(lv_objnr)
            FROM cobrb
           WHERE objnr = @ls_aufk_aiil-objnr
             AND konty = 'SK'.  "G/L
          CHECK sy-subrc NE 0.

          "Get HKCG Internal Order's settlement rules
          SELECT objnr, lfdnr, perbz, urzuo, prozs, konty, hkont
            INTO TABLE @DATA(lt_cobrb)
            FROM cobrb
           WHERE objnr = @<fs_aufk>-objnr
             AND konty = 'SK'.  "G/L
          SORT lt_cobrb BY objnr lfdnr.

          LOOP AT lt_cobrb ASSIGNING FIELD-SYMBOL(<fs_cobrb>).
            APPEND INITIAL LINE TO mt_interal_order ASSIGNING FIELD-SYMBOL(<fs_order>).
            MOVE-CORRESPONDING <fs_cobrb> TO <fs_order>.
            <fs_order>-psphi = <fs_wbs_data>-psphi.
            <fs_order>-posid = lv_wbs_aiil.
            <fs_order>-kostl = p_kostl.
            <fs_order>-aufnr = lv_aufnr.
            <fs_order>-objnr_aiil = ls_aufk_aiil-objnr.
          ENDLOOP.

          CLEAR lt_cobrb.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
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
        lr_columns->get_column( 'POST1' )->set_technical( ).
        lr_columns->get_column( 'OBJNR_AIIL' )->set_technical( ).

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
        lv_question = `Change AIIL internal order's settlement rules in bulk?`.
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

        change_iorder_settl_rule( ).

        mr_salv_table->get_columns( )->set_optimize( ).
        mr_salv_table->refresh( ).
    ENDCASE.
  ENDMETHOD.

  METHOD change_iorder_settl_rule.
    DATA lv_msg TYPE string.
    DATA lv_text TYPE string.

    LOOP AT mt_interal_order ASSIGNING FIELD-SYMBOL(<fs_iorder>).
      CHECK <fs_iorder>-message_type NE c_icon_green.

      AT NEW aufnr.
        CLEAR: lv_text, lv_msg.

        lv_text = |Processing internal order { <fs_iorder>-aufnr ALPHA = OUT } ...|.
        CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
          EXPORTING
            text = lv_text.

        lv_msg = call_ko02_bdc( is_iorder_settl_rule = <fs_iorder> ).
      ENDAT.

      IF lv_msg IS NOT INITIAL.
        <fs_iorder>-message_type = c_icon_red.
        <fs_iorder>-message = lv_msg.
      ELSE.
        <fs_iorder>-message_type = c_icon_green.
        <fs_iorder>-message = 'The internal order has been changed successfully'.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD call_ko02_bdc.

    DATA ls_opt TYPE ctu_params.
    DATA lv_index TYPE numc2.
    DATA lv_message TYPE string.
    DATA lv_fval TYPE bdc_fval.
    DATA lv_objnr TYPE cobrb-objnr.

    CLEAR: mt_bdcdata, mt_messtab.

    bdc_dynpro( program = 'SAPMKAUF' dynpro = '0110' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '/00' ).
    bdc_field( fnam = 'COAS-AUFNR' fval = CONV #( is_iorder_settl_rule-aufnr ) ).

    bdc_dynpro( program = 'SAPMKAUF' dynpro = '0600' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '=ABVO' ).
    bdc_field( fnam = 'COAS-PSPEL' fval = CONV #( is_iorder_settl_rule-posid ) ).

* Maintain Settlement Rule's parameters
    bdc_dynpro( program = 'SAPLKOBS' dynpro = '0130' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '=PARA' ).

    bdc_dynpro( program = 'SAPLKOBS' dynpro = '0110' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '=BACK' ).
    bdc_field( fnam = 'COBRA-APROF' fval = '90' ).  "Settlement profile
    bdc_field( fnam = 'COBRA-ABSCH' fval = 'PS' ).  "Allocation structure
    bdc_field( fnam = 'COBRA-ERSCH' fval = '' ). "PA transfer str
    bdc_field( fnam = 'COBRA-URSCH' fval = 'PS' ).  "Source structure
    bdc_field( fnam = 'COBRA-HIENR' fval = '' ).  "Hierarchy number

    SELECT objnr, bureg, lfdnr, konty
      FROM cobrb
      INTO TABLE @DATA(lt_cobrb)
     WHERE objnr = @is_iorder_settl_rule-objnr_aiil.

    READ TABLE lt_cobrb TRANSPORTING NO FIELDS WITH KEY konty = 'OR'.
    IF sy-subrc = 0.
* End 'ORD' settlement rule
      lv_index = sy-tabix.
      bdc_dynpro( program = 'SAPLKOBS' dynpro = '0130' ).
      bdc_field( fnam = 'BDC_OKCODE' fval = '/00' ).
      bdc_field( fnam = |COBRB-GBISP({ lv_index })| fval = CONV #( sy-datum+4(2) ) ).
      bdc_field( fnam = |COBRB-GBISJ({ lv_index })| fval = CONV #( sy-datum+0(4) ) ).
    ENDIF.

    lv_index = lines( lt_cobrb ).
    LOOP AT mt_interal_order ASSIGNING FIELD-SYMBOL(<fs_iorder>).
      lv_index = lv_index + 1.
      bdc_dynpro( program = 'SAPLKOBS' dynpro = '0130' ).
      bdc_field( fnam = 'BDC_OKCODE' fval = '=DETA' ).
      lv_fval = conversion_exit_obart_output( <fs_iorder>-konty ).
      CONDENSE lv_fval.
      bdc_field( fnam = |COBRB-KONTY({ lv_index })| fval = lv_fval ).
      bdc_field( fnam = |DKOBR-EMPGE({ lv_index })| fval = CONV #( <fs_iorder>-hkont ) ).
      lv_fval = CONV #( <fs_iorder>-prozs ).
      CONDENSE lv_fval.
      bdc_field( fnam = |COBRB-PROZS({ lv_index })| fval = lv_fval ).
      lv_fval = conversion_exit_perbz_output( <fs_iorder>-perbz ).
      CONDENSE lv_fval.
      bdc_field( fnam = |COBRB-PERBZ({ lv_index })| fval = lv_fval ).
      bdc_field( fnam = |COBRB-URZUO({ lv_index })| fval = CONV #( <fs_iorder>-urzuo ) ).

      bdc_dynpro( program = 'SAPLKOBS' dynpro = '0100' ).
      bdc_field( fnam = 'BDC_OKCODE' fval = '=BACK' ).
      bdc_field( fnam = 'COBL-KOSTL' fval = CONV #( <fs_iorder>-kostl ) ).
    ENDLOOP.

    " Final save and exit
    bdc_dynpro( program = 'SAPLKOBS' dynpro = '0130' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '/00' ).

    " Final save and exit
    bdc_dynpro( program = 'SAPLKOBS' dynpro = '0130' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '/00' ).

    bdc_dynpro( program = 'SAPLKOBS' dynpro = '0130' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '=BACK' ).

    bdc_dynpro( program = 'SAPMKAUF' dynpro = '0600' ).
    bdc_field( fnam = 'BDC_OKCODE' fval = '=SICH' ).

    " Execute BDC transaction
    ls_opt-dismode = 'N'.
    ls_opt-updmode = 'S'.
    ls_opt-defsize = 'X'.
    ls_opt-racommit = 'X'.

    CALL TRANSACTION 'KO02' USING mt_bdcdata
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
    ELSE.
      DO 5 TIMES.
        SELECT SINGLE objnr INTO lv_objnr
          FROM cobrb
         WHERE objnr = is_iorder_settl_rule-objnr_aiil
           AND konty = 'SK'.  "G/L
        IF sy-subrc <> 0.
          WAIT UP TO 1 SECONDS.
        ELSE.
          EXIT.
        ENDIF.
      ENDDO.

      IF lv_objnr IS INITIAL.
        cv_message = |The internal order could not be changed due to an unknown reason. Please contact IT support.|.
      ENDIF.
    ENDIF.

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

  METHOD bdc_dynpro.

    APPEND INITIAL LINE TO mt_bdcdata ASSIGNING FIELD-SYMBOL(<fs_bdcdata>).
    <fs_bdcdata>-program  = program.
    <fs_bdcdata>-dynpro   = dynpro.
    <fs_bdcdata>-dynbegin = 'X'.

  ENDMETHOD.

  METHOD bdc_field.

    APPEND INITIAL LINE TO mt_bdcdata ASSIGNING FIELD-SYMBOL(<fs_bdcdata>).
    <fs_bdcdata>-fnam  = fnam.
    <fs_bdcdata>-fval  = fval.

  ENDMETHOD.


ENDCLASS.
