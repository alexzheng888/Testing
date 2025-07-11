*&---------------------------------------------------------------------*
*& Program Name     : ZPRRP020                                         *
*& Title            : Automatically generate cross company FI posting  *
*                       to transfer cost from HKCG to AIIL             *
*& Module Name      : CO                                               *
*& Author           : Alex Zheng                                       *
*& Create Date      : 01.07.2025                                       *
*& Logical DB       : None                                             *
*& Program Type     : Report                                           *
*&---------------------------------------------------------------------*
*& MODIFICATION LOG                                                    *
*&                                                                     *
*& LOG#  DATE        AUTHOR        DESCRIPTION                         *
*& ----  ----        ------        -----------                         *
*& 0000  01.07.2025  Dynasys       Initial Implementation              *
*&---------------------------------------------------------------------*
REPORT zprrp020.

TABLES: proj, prps, cskb, bkpf.
DATA ok_code TYPE sy-tcode.

*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE text-001.
* SELECT-OPTIONS: s_proj   FOR prps-psphi OBLIGATORY MATCHCODE OBJECT prsm,
SELECT-OPTIONS: s_proj   FOR proj-pspid OBLIGATORY,
                s_wbs    FOR prps-posid MATCHCODE OBJECT prpm,
                s_erdat  FOR prps-erdat,
                s_budat  FOR prps-erdat OBLIGATORY NO-EXTENSION,
                s_kstar  FOR cskb-kstar OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b01.

SELECTION-SCREEN BEGIN OF BLOCK b02 WITH FRAME TITLE text-002.
PARAMETERS: p_opt1 RADIOBUTTON GROUP opt DEFAULT 'X' USER-COMMAND opt,
            p_opt2 RADIOBUTTON GROUP opt.
SELECTION-SCREEN END OF BLOCK b02.


*----------------------------------------------------------------------*
* CLASS DEFINITION
*----------------------------------------------------------------------*
CLASS lcl_main DEFINITION.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_cji3_result,
             bldat  TYPE kaep_coac-bldat,    "Document Date
             budat  TYPE kaep_coac-budat,    "Posting Date
             obart  TYPE kaep_coac-obart,    "Object Type
             pspid  TYPE kaep_coac-pspid,    "Project Define
             objid  TYPE kaep_coac-objid,    "Internal Order
             kstar  TYPE kaep_coac-kstar,    "Cost Element
             kwaer  TYPE kaep_coac-kwaer,    "Controlling area currency
             wkgbtr TYPE kaep_coac-wkgbtr,  "Total Value in Controlling Area Currency
           END OF ty_cji3_result,
           BEGIN OF ty_out,
             pspid        TYPE kaep_coac-pspid,    "Project Define
             bschl        TYPE bseg-bschl,
             newbk        TYPE bseg-bukrs,
             hkont        TYPE bseg-hkont,
             wkgbtr       TYPE kaep_coac-wkgbtr,
             kwaer        TYPE kaep_coac-kwaer,    "Controlling area currency
             aufnr        TYPE aufk-aufnr,
             obj_key      TYPE bapiache09-obj_key,
             message_type TYPE icon_d,       "Message Type Icon
             message      TYPE bapi_msg,        "Message
           END OF ty_out.
    TYPES: tty_cji3_result TYPE TABLE OF ty_cji3_result WITH EMPTY KEY,
           tty_out         TYPE TABLE OF ty_out WITH EMPTY KEY.

    METHODS:
      constructor,
      main_processing.

  PRIVATE SECTION.
    DATA mt_iorder TYPE RANGE OF aufnr.
    DATA mr_salv_table    TYPE REF TO cl_salv_table.
    DATA mt_out TYPE tty_out.
    DATA mv_log_handle TYPE balloghndl.
    DATA mt_proj TYPE RANGE OF ps_posid.
    DATA mv_executed TYPE char1.

    CONSTANTS: c_company_hkcg TYPE bukrs VALUE 'HKCG',
               c_company_aiil TYPE bukrs VALUE 'AIIL',
               c_icon_green   TYPE icon_d VALUE '@08@',
               c_icon_red     TYPE icon_d VALUE '@0A@',
               c_icon_yellow  TYPE icon_d VALUE '@09@'.

    METHODS:
      get_hkcg_iorder,
      prepare_output_data,
      get_aiil_wbs_naming
        IMPORTING iv_hkcg_wbs    TYPE ps_posid
        EXPORTING ev_aiil_wbs    TYPE ps_posid
                  ev_hkcg_suffix TYPE char1,
      display_alv
        IMPORTING iv_title TYPE string OPTIONAL
        CHANGING  it_data  TYPE ANY TABLE,
      on_user_command FOR EVENT added_function OF cl_salv_events
        IMPORTING e_salv_function,
      on_single_click FOR EVENT link_click OF cl_salv_events_table
        IMPORTING row column,
      generate_cross_company_fidoc,
      message_init,
      message_store IMPORTING is_msg TYPE bapiret2,
      message_show.
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
    get_hkcg_iorder( ).

    prepare_output_data( ).

    IF sy-batch EQ 'X'.
      CLEAR bkpf.
      bkpf = VALUE #(
        bukrs = c_company_hkcg
        waers = 'HKD'
        blart = 'SA'
        bldat = sy-datum
        budat = sy-datum ).

      generate_cross_company_fidoc( ).
    ENDIF.

    display_alv( CHANGING it_data = mt_out ).
  ENDMETHOD.

  METHOD get_hkcg_iorder.
    DATA lv_suffix TYPE char1.

    SELECT a~pspnr, a~posid, a~post1, a~objnr, a~psphi, b~pspid
      FROM prps AS a
        INNER JOIN proj AS b ON b~pspnr = a~psphi
      INTO TABLE @DATA(lt_hkcg_wbs)
      WHERE a~posid IN @s_wbs
*        AND psphi IN @s_proj
        AND a~erdat IN @s_erdat
        AND a~pbukr = @c_company_hkcg
        AND b~pspid IN @s_proj
        AND b~vbukr = @c_company_hkcg.

    IF lt_hkcg_wbs[] IS NOT INITIAL.
      SELECT *
        INTO TABLE @DATA(lt_jest)
        FROM jest
        FOR ALL ENTRIES IN @lt_hkcg_wbs
       WHERE objnr = @lt_hkcg_wbs-objnr
         AND stat  = 'I0046' "Closed
         AND inact = ''.
      SORT lt_jest BY objnr.
    ENDIF.

    LOOP AT lt_hkcg_wbs ASSIGNING FIELD-SYMBOL(<fs_wbs_data>).
      DATA(lv_tabix) = sy-tabix.
      CLEAR: lv_suffix.

      get_aiil_wbs_naming(
        EXPORTING iv_hkcg_wbs = <fs_wbs_data>-posid
        IMPORTING ev_hkcg_suffix = lv_suffix ).

      IF lv_suffix NA 'AGK'.
        DELETE lt_hkcg_wbs INDEX lv_tabix.
        CONTINUE.
      ENDIF.

      READ TABLE lt_jest TRANSPORTING NO FIELDS
        WITH KEY objnr = <fs_wbs_data>-objnr BINARY SEARCH.
      IF sy-subrc = 0.
        DELETE lt_hkcg_wbs INDEX lv_tabix.
        CONTINUE.
      ENDIF.

      APPEND INITIAL LINE TO mt_proj ASSIGNING FIELD-SYMBOL(<fs_proj>).
      <fs_proj>-sign = 'I'.
      <fs_proj>-option = 'EQ'.
      <fs_proj>-low = <fs_wbs_data>-pspid.

    ENDLOOP.

    SORT mt_proj.
    DELETE ADJACENT DUPLICATES FROM mt_proj COMPARING ALL FIELDS.

    IF lt_hkcg_wbs IS NOT INITIAL.
      SELECT aufnr
        FROM aufk
        FOR ALL ENTRIES IN @lt_hkcg_wbs
      WHERE pspel = @lt_hkcg_wbs-pspnr
        INTO TABLE @DATA(lt_aufk).

      LOOP AT lt_aufk ASSIGNING FIELD-SYMBOL(<fs_aufk>).
        APPEND INITIAL LINE TO mt_iorder ASSIGNING FIELD-SYMBOL(<fs_iorder>).
        <fs_iorder>-sign = 'I'.
        <fs_iorder>-option = 'EQ'.
        <fs_iorder>-low = <fs_aufk>-aufnr.
      ENDLOOP.
    ENDIF.

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

  METHOD prepare_output_data.
    DATA cn_projn TYPE RANGE OF ps_pspid.
    DATA cn_netnr TYPE RANGE OF aufnr.
    DATA r_kstar TYPE RANGE OF kstar.
    DATA r_budat TYPE RANGE OF co_budat.
    DATA cn_profd TYPE ps_prof_db.
    DATA p_disvar TYPE slis_vari.
    DATA lr_alv_data TYPE REF TO data.
    DATA lt_cji3_result TYPE tty_cji3_result.
    DATA lv_msg TYPE string.
    DATA lt_iorder_amount TYPE STANDARD TABLE OF ty_cji3_result.
    DATA ls_iorder_amount TYPE ty_cji3_result.
    DATA lv_aufnr_aiil TYPE aufk-aufnr.

    FIELD-SYMBOLS <ft_alv_data> TYPE ANY TABLE.

    CHECK mt_iorder IS NOT INITIAL.

    cl_salv_bs_runtime_info=>clear_all( ).

    cl_salv_bs_runtime_info=>set(
      EXPORTING display  = abap_false
                metadata = abap_true
                data     = abap_true ).

    cn_projn = mt_proj[].
    cn_netnr = mt_iorder.
    r_kstar  = s_kstar[].
    r_budat  = s_budat[].
    cn_profd = '000000000001'.
    p_disvar = '1SAP'.
    SET PARAMETER ID 'CAC' FIELD 'HKCG'.

    SUBMIT rkpep003
      AND RETURN
           WITH cn_projn IN cn_projn
           WITH cn_netnr IN cn_netnr
           WITH r_kstar  IN r_kstar
           WITH r_budat  IN r_budat
           WITH cn_profd = cn_profd
           WITH p_disvar = p_disvar.

* retrieve the ALV data
    TRY.
        cl_salv_bs_runtime_info=>get_data_ref(
          IMPORTING r_data = lr_alv_data ).
        ASSIGN lr_alv_data->* TO <ft_alv_data>.
        IF <ft_alv_data> IS ASSIGNED AND <ft_alv_data> IS NOT INITIAL.
          MOVE-CORRESPONDING <ft_alv_data> TO lt_cji3_result.
          DELETE lt_cji3_result WHERE obart NE 'OR'.
          LOOP AT lt_cji3_result ASSIGNING FIELD-SYMBOL(<fs_cji3_result>).
            CLEAR ls_iorder_amount.
            ls_iorder_amount-pspid = <fs_cji3_result>-pspid.
            ls_iorder_amount-kstar = <fs_cji3_result>-kstar.
            ls_iorder_amount-objid = <fs_cji3_result>-objid.
            ls_iorder_amount-kwaer = <fs_cji3_result>-kwaer.
            ls_iorder_amount-wkgbtr = <fs_cji3_result>-wkgbtr.
            COLLECT ls_iorder_amount INTO lt_iorder_amount.
          ENDLOOP.

          SORT lt_iorder_amount BY pspid kstar objid kwaer.
          LOOP AT lt_iorder_amount ASSIGNING FIELD-SYMBOL(<fs_iorder_amount>)
                                   WHERE wkgbtr IS NOT INITIAL.
            lv_aufnr_aiil = <fs_iorder_amount>-objid && 'A'.
            SELECT SINGLE aufnr INTO lv_aufnr_aiil FROM aufk
              WHERE aufnr = lv_aufnr_aiil AND pspel NE '00000000'.
            CHECK sy-subrc = 0.

            APPEND INITIAL LINE TO mt_out ASSIGNING FIELD-SYMBOL(<fs_out>).
            <fs_out>-pspid = <fs_iorder_amount>-pspid.
            <fs_out>-bschl = '50'.
            <fs_out>-hkont = <fs_iorder_amount>-kstar.
            <fs_out>-wkgbtr = <fs_iorder_amount>-wkgbtr.
            <fs_out>-kwaer = <fs_iorder_amount>-kwaer.
            <fs_out>-aufnr = <fs_iorder_amount>-objid.

            APPEND INITIAL LINE TO mt_out ASSIGNING <fs_out>.
            <fs_out>-pspid = <fs_iorder_amount>-pspid.
            <fs_out>-bschl = '40'.
            <fs_out>-newbk = c_company_aiil.
            <fs_out>-hkont = <fs_iorder_amount>-kstar.
            <fs_out>-wkgbtr = <fs_iorder_amount>-wkgbtr.
            <fs_out>-kwaer = <fs_iorder_amount>-kwaer.
            <fs_out>-aufnr = lv_aufnr_aiil.
          ENDLOOP.
        ENDIF.
      CATCH cx_salv_bs_sc_runtime_info INTO DATA(lx_error).
        lv_msg = lx_error->get_text( ).
        MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.

    cl_salv_bs_runtime_info=>clear_all( ).

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
          lr_functions       TYPE REF TO cl_salv_functions_list,
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

        lr_functions = mr_salv_table->get_functions( ).
        lr_functions->set_sort_asc( abap_false ).
        lr_functions->set_sort_desc( abap_false ).

        lr_columns = mr_salv_table->get_columns( ).
* optimize columns' width
        lr_columns->set_optimize( value = abap_true ).
* fix key columns
        lr_columns->set_key_fixation( value = abap_true ).

*... set hotspot column
        lr_column ?= lr_columns->get_column( 'OBJ_KEY' ).
        lr_column->set_cell_type( if_salv_c_cell_type=>hotspot ).
        lr_columns->get_column( 'OBJ_KEY' )->set_long_text( 'FI Doc.' ).

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
        SET HANDLER on_single_click FOR lr_events.

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
        CLEAR bkpf.
        bkpf = VALUE #(
          bukrs = c_company_hkcg
          waers = 'HKD'
          blart = 'SA'
          bldat = sy-datum
          budat = sy-datum ).

        CALL SCREEN 900 STARTING AT 25 4.
        CHECK ok_code EQ '&ZOK'.

        generate_cross_company_fidoc( ).

        mr_salv_table->get_columns( )->set_optimize( ).
        mr_salv_table->refresh( ).
    ENDCASE.
  ENDMETHOD.

  METHOD on_single_click.
    READ TABLE mt_out ASSIGNING FIELD-SYMBOL(<fs_out>) INDEX row.
    IF sy-subrc = 0 AND <fs_out>-obj_key IS NOT INITIAL.
      SET PARAMETER ID: 'BLN' FIELD <fs_out>-obj_key+0(10),
                        'BUK' FIELD <fs_out>-obj_key+10(4),
                        'GJR' FIELD <fs_out>-obj_key+14(4).
      TRY.
          CALL TRANSACTION 'FB03' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
        CATCH cx_sy_authorization_error INTO DATA(lx_error).
          MESSAGE lx_error->get_text( ) TYPE 'E'.
          RETURN.
      ENDTRY.
    ENDIF.
  ENDMETHOD.

  METHOD generate_cross_company_fidoc.
    DATA obj_key TYPE bapiache09-obj_key.
    DATA lt_return TYPE STANDARD TABLE OF bapiret2.
    DATA ls_return TYPE bapiret2.
    DATA documentheader TYPE bapiache09.
    DATA accountgl TYPE STANDARD TABLE OF bapiacgl09.
    DATA currencyamount TYPE STANDARD TABLE OF bapiaccr09.
    DATA lv_item TYPE bapiacgl09-itemno_acc.
    DATA lv_msg TYPE string.

    message_init( ).
    SET COUNTRY 'HK'.

    DATA(lt_out) = mt_out.
    DELETE lt_out WHERE obj_key IS NOT INITIAL.
    LOOP AT lt_out ASSIGNING FIELD-SYMBOL(<fs_out>).
      AT NEW pspid.
        CLEAR: documentheader, accountgl, currencyamount, obj_key,
               lt_return, lv_item, lv_msg.
        documentheader-username    = sy-uname.
        documentheader-comp_code   = bkpf-bukrs.
        documentheader-doc_type    = bkpf-blart.
        documentheader-doc_date    = bkpf-bldat.
        documentheader-pstng_date  = bkpf-budat.

        CALL FUNCTION 'CONVERSION_EXIT_ABPSN_OUTPUT'
          EXPORTING
            input  = <fs_out>-pspid
          IMPORTING
            output = documentheader-header_txt.
        documentheader-bus_act     = 'RFBU'.
      ENDAT.

      APPEND INITIAL LINE TO accountgl ASSIGNING FIELD-SYMBOL(<fs_accountgl>).
      lv_item = lv_item + 1.
      <fs_accountgl>-itemno_acc = lv_item.
      <fs_accountgl>-gl_account = <fs_out>-hkont.
      <fs_accountgl>-orderid = <fs_out>-aufnr.
      <fs_accountgl>-comp_code = COND #( WHEN <fs_out>-bschl = '50' THEN '' ELSE c_company_aiil ).
      IF p_opt1 = 'X'.
        <fs_accountgl>-item_text  = |{ s_budat-low DATE = ENVIRONMENT } ~ { s_budat-high DATE = ENVIRONMENT }|.
      ELSE.
        <fs_accountgl>-item_text  = |{ sy-datum DATE = ENVIRONMENT }|.
      ENDIF.

      APPEND INITIAL LINE TO currencyamount ASSIGNING FIELD-SYMBOL(<fs_currencyamount>).
      <fs_currencyamount>-itemno_acc  = lv_item.
      <fs_currencyamount>-curr_type   = '00'." Doc. Curr.
      <fs_currencyamount>-currency    = <fs_out>-kwaer.
      IF <fs_out>-bschl = '50'.
        <fs_currencyamount>-amt_doccur = <fs_out>-wkgbtr * -1.
      ELSE.
        <fs_currencyamount>-amt_doccur = <fs_out>-wkgbtr.
      ENDIF.

      AT END OF pspid.
        CLEAR ls_return.
        ls_return = VALUE #(
          type = 'I' id = 'Z1' number = '001'
          message_v1 = '=============='
          message_v2 = 'Processing Project'
          message_v3 = <fs_out>-pspid
          message_v4 = '=============='
           ).
        message_store( ls_return ).
        CALL FUNCTION 'BAPI_ACC_DOCUMENT_CHECK'
          EXPORTING
            documentheader = documentheader
          TABLES
            accountgl      = accountgl
            currencyamount = currencyamount
            return         = lt_return.

        LOOP AT lt_return ASSIGNING FIELD-SYMBOL(<fs_return>)
                          WHERE type CA 'EAX'.
          message_store( <fs_return> ).
          CONCATENATE lv_msg <fs_return>-message INTO lv_msg SEPARATED BY space.
        ENDLOOP.
        IF sy-subrc NE 0.
          CALL FUNCTION 'BAPI_ACC_DOCUMENT_POST'
            EXPORTING
              documentheader = documentheader
            IMPORTING
              obj_key        = obj_key
            TABLES
              accountgl      = accountgl
              currencyamount = currencyamount
              return         = lt_return.

          IF obj_key IS NOT INITIAL AND obj_key NE '$'.
            CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
              EXPORTING
                wait = 'X'.
          ELSE.
            CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
            DELETE lt_return WHERE type NA 'EAX'.
          ENDIF.

          LOOP AT lt_return ASSIGNING <fs_return>.
            message_store( <fs_return> ).
            CONCATENATE lv_msg <fs_return>-message INTO lv_msg SEPARATED BY space.
          ENDLOOP.
          CONDENSE lv_msg.

          LOOP AT mt_out ASSIGNING FIELD-SYMBOL(<fs_out2>) WHERE pspid = <fs_out>-pspid.
            IF obj_key IS NOT INITIAL AND obj_key NE '$'.
              <fs_out2>-obj_key = obj_key.
              <fs_out2>-message_type = c_icon_green.
            ELSE.
              <fs_out2>-message_type = c_icon_red.
              <fs_out2>-message = lv_msg.
            ENDIF.
          ENDLOOP.
        ELSE.
          CONDENSE lv_msg.
          LOOP AT mt_out ASSIGNING <fs_out2> WHERE pspid = <fs_out>-pspid.
            <fs_out2>-message_type = c_icon_red.
            <fs_out2>-message = lv_msg.
          ENDLOOP.
        ENDIF.
      ENDAT.
    ENDLOOP.

    CHECK sy-batch = ''.
    message_show( ).

  ENDMETHOD.


  METHOD message_init.

    DATA ls_log TYPE bal_s_log.

    CLEAR mv_log_handle.
    ls_log-extnumber = 'Application Log'.                   "#EC NOTEXT
    ls_log-aluser    = sy-uname.
    ls_log-alprog    = sy-repid.

* create a log
    CALL FUNCTION 'BAL_LOG_CREATE'
      EXPORTING
        i_s_log      = ls_log
      IMPORTING
        e_log_handle = mv_log_handle
      EXCEPTIONS
        OTHERS       = 1.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    ENDIF.

  ENDMETHOD.

  METHOD message_store.
    DATA ls_msg TYPE bal_s_msg.

    ls_msg-msgty     = is_msg-type.
    ls_msg-msgid     = is_msg-id.
    ls_msg-msgno     = is_msg-number.
    ls_msg-msgv1     = is_msg-message_v1.
    ls_msg-msgv2     = is_msg-message_v2.
    ls_msg-msgv3     = is_msg-message_v3.
    ls_msg-msgv4     = is_msg-message_v4.

    CALL FUNCTION 'BAL_LOG_MSG_ADD'
      EXPORTING
        i_log_handle  = mv_log_handle
        i_s_msg       = ls_msg
      EXCEPTIONS
        log_not_found = 0
        OTHERS        = 1.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    ENDIF.

  ENDMETHOD.

  METHOD message_show.
    DATA lt_log_handle TYPE bal_t_logh.

    APPEND mv_log_handle TO lt_log_handle.

    CALL FUNCTION 'BAL_DSP_LOG_DISPLAY'
      EXPORTING
        i_t_log_handle = lt_log_handle
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    ENDIF.

  ENDMETHOD.
ENDCLASS.
*&---------------------------------------------------------------------*
*&      Module  STATUS_0900  OUTPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
MODULE status_0900 OUTPUT.
  SET PF-STATUS 'STATUS_900'.
  SET TITLEBAR 'T_900'.
ENDMODULE.
*&---------------------------------------------------------------------*
*&      Module  USER_COMMAND_0900  INPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
MODULE user_command_0900 INPUT.
  CASE ok_code.
    WHEN '&ZOK' OR '&ZCAN'.
      SET SCREEN 0. LEAVE SCREEN.
  ENDCASE.
ENDMODULE.
