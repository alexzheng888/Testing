*&---------------------------------------------------------------------*
*& Report ZPRRP019
*&---------------------------------------------------------------------*
*&
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
             post1        TYPE prps-post1,    "Description
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
             posid_hkcg   TYPE prps-posid,    "HKCG WBS Element
             objnr_hkcg   TYPE prps-objnr,    "HKCG Object Number
             executed     TYPE char1,
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

    SORT mt_wbs_data BY psphi posid.

    LOOP AT mt_wbs_data ASSIGNING FIELD-SYMBOL(<fs_wbs_data>).
      AT NEW pspnr.
        SELECT pspel, aufnr, a~objnr, concat( aufnr, 'A' ) AS aufnr_a
          FROM aufk as a
           INNER JOIN @mt_wbs_data as b on b~pspnr = a~pspel
          INTO TABLE @DATA(lt_aufk).
        SORT lt_aufk BY pspel aufnr.

        LOOP AT lt_aufk ASSIGNING FIELD-SYMBOL(<fs_aufk>).

        ENDLOOP.
      ENDAT.
    ENDLOOP.
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

        mr_salv_table->get_columns( )->set_optimize( ).
        mr_salv_table->refresh( ).
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
