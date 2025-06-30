
*&---------------------------------------------------------------------*
*& Report YTEMP_DEMO_009
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ytemp_demo_009.

DATA lr_alv_data TYPE REF TO data.
FIELD-SYMBOLS <lt_alv_data> TYPE ANY TABLE.

cl_salv_bs_runtime_info=>clear_all( ).

cl_salv_bs_runtime_info=>set(
  EXPORTING display  = abap_false
            metadata = abap_true
            data     = abap_true ).

DATA cn_projn TYPE RANGE OF ps_pspid.
DATA cn_netnr TYPE RANGE OF aufnr.
DATA r_kstar TYPE RANGE OF kstar.
DATA r_budat TYPE RANGE OF co_budat.
DATA cn_profd TYPE ps_prof_db.
DATA p_disvar TYPE slis_vari.

cn_projn = VALUE #( ( sign = 'I' option = 'EQ' low = '' ) ).
cn_netnr = VALUE #( ( sign = 'I' option = 'EQ' low = '' ) ).
r_kstar = VALUE #( ( sign = 'I' option = 'EQ' low = '' ) ).
r_budat = VALUE #( ( sign = 'I' option = 'BT' low = '20140501' high = '20250630' ) ).
cn_profd = '000000000001'.
p_disvar = '1SAP'.

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
    ASSIGN lr_alv_data->* TO <lt_alv_data>.
  CATCH cx_salv_bs_sc_runtime_info.
*    MESSAGE ID 'HCMFAB_MYREPORTING' TYPE 'E' NUMBER '002' INTO lv_message_text.
*    ls_message = cl_hcmfab_reporting_utility=>fill_message( lv_message_text ).
*    APPEND ls_message TO et_messages.
*    RETURN.
ENDTRY.

cl_salv_bs_runtime_info=>clear_all( ).
