

          lr_functions       TYPE REF TO cl_salv_functions_list,


        lr_functions = mr_salv_table->get_functions( ).
        lr_functions->set_sort_asc( abap_false ).
        lr_functions->set_sort_desc( abap_false ).
