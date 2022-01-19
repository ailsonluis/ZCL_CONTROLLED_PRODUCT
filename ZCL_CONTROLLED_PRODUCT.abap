class ZCL_CONTROLLED_PRODUCT definition
  public
  final
  create public .

public section.

  methods CHECK_MATERIAL
    importing
      !I_MATNR type MATNR
      !I_PARTNER type BU_PARTNER
      !I_WERKS type WERKS_D
      !I_QTYMOV type MENGE_D
      !I_REVERSAL type XSTBW optional
    returning
      value(RE_BAPIRET2) type BAPIRET2 .
  methods GET_STOCK
    importing
      !I_MATNR type MATNR
      !I_WERKS type WERKS_D
    returning
      value(RE_STOCK) type /SAPAPO/PT_T_STOCK .
protected section.

  constants C_EXERCITO_PRODUCT type CHAR3 value 'CEX' ##NO_TEXT.
  constants C_EXERCITO_LICENSE type CHAR6 value 'ZF0002' ##NO_TEXT.
  constants C_PFEDERAL_PRODUCT type CHAR3 value 'CPF' ##NO_TEXT.
  constants C_PFEDERAL_LICENSE_F type CHAR6 value 'ZF0001' ##NO_TEXT.
  constants C_PFEDERAL_LICENSE_C type CHAR6 value 'ZC0003' ##NO_TEXT.
  private section.

ENDCLASS.



CLASS ZCL_CONTROLLED_PRODUCT IMPLEMENTATION.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_CONTROLLED_PRODUCT->CHECK_MATERIAL
* +-------------------------------------------------------------------------------------------------+
* | [--->] I_MATNR                        TYPE        MATNR
* | [--->] I_PARTNER                      TYPE        BU_PARTNER
* | [--->] I_WERKS                        TYPE        WERKS_D
* | [--->] I_QTYMOV                       TYPE        MENGE_D
* | [--->] I_REVERSAL                     TYPE        XSTBW(optional)
* | [<-()] RE_BAPIRET2                    TYPE        BAPIRET2
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method check_material.

    "Seleciona dados de materials para validar se o material é controlado
    select single matnr, profl, zeinr  from mara
      into @data(ls_mara)
      where matnr = @i_matnr.


    "Seleciona dados do parceiro para validar se possui certificado

    select partner, type, idnumber, valid_date_from, valid_date_to  from but0id
       into table @data(lt_license)
       where partner = @i_partner and
        ( valid_date_from <= @sy-datum and
          valid_date_to >= @sy-datum ).

    "Se controlado pelo exercito valida se fornecedor possui licença valida:
    if ls_mara-profl eq c_exercito_product.

      if sy-tcode = 'J1B1N'.
        re_bapiret2 = value #(
          type = 'E'
          id = 'ZMM'
          number = '018'
          message_v1 = ls_mara-matnr
          "message = |Material controlado pelo Exército! NF Writer não permitida! |
          ).
          exit.
      endif.

      if line_exists( lt_license[ type = c_exercito_license ] ).
        "Check estoque apenas para compras!
        "se quantidade informa e nao é estorno
        if i_qtymov > 0 and i_reversal = abap_false.
            data(lv_stock) = me->get_stock( EXPORTING i_matnr = ls_mara-matnr i_werks = i_werks  ).
            data(lv_stock_foreseen) = lv_stock + i_qtymov.

            if lv_stock_foreseen > ls_mara-zeinr .

              re_bapiret2 = value #(
              type = 'E'
              id = 'ZMM'
              number = '017'
              "message = |Saldo em estoque será maior que o máximo permitido pelo Exército!  |
              message_v1 = |{ ls_mara-matnr ALPHA = OUT }|
              message_v2 = |Estq.Previsto: { lv_stock_foreseen } QtdMaxPermitida: { ls_mara-zeinr } |


             ) .
             exit.
            endif.
        endif.

      else.
        "Parceiro não possui licença valida
         re_bapiret2 = value #(
          type = 'E'
          id = 'ZMM'
          number = '016'
          "message = |Parceiro { i_partner ALPHA = OUT } não possui licença do Exército válida! |
          message_v1 = | { i_partner ALPHA = OUT } |
          message_v2 = | Exército |
         ) .
        exit.
      endif.

    endif.

    if ls_mara-profl eq c_pfederal_product.

      if line_exists( lt_license[ type = c_pfederal_license_f ] ) or line_exists( lt_license[ type = c_pfederal_license_c ] ).
        "Material controlado pela PF não valida estoque max
        "possui licença ZF0001 or ZC0003
        exit.
      else.
        "Parceiro não possui licença valida.
         re_bapiret2 = value #(
          type = 'E'
          id = 'ZMM'
          number = '016'
          "message = |Parceiro { i_partner ALPHA = OUT } não possui licença da PF válida! |
          message_v1 = | { i_partner ALPHA = OUT } |
          message_v2 = | Pol.Federal |
         ) .
        exit.
      endif.

    endif.




    "retorna tipo de controle e saldo em estoque

  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_CONTROLLED_PRODUCT->GET_STOCK
* +-------------------------------------------------------------------------------------------------+
* | [--->] I_MATNR                        TYPE        MATNR
* | [--->] I_WERKS                        TYPE        WERKS_D
* | [<-()] RE_STOCK                       TYPE        /SAPAPO/PT_T_STOCK
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method get_stock.
    "Verifica o saldo total em estoque.
    data:
      ls_mrp_list          type  bapi_mrp_list,
      ls_mrp_control_param type  bapi_mrp_control_param,
      ls_stock             type bapi_mrp_stock_detail,
      ls_return            type  bapiret2.

    data(lv_matnr) = conv matnr18( i_matnr ).

    call function 'BAPI_MATERIAL_STOCK_REQ_LIST'
      exporting
        material         = lv_matnr
        plant            = i_werks
      importing
        " mrp_list          = ls_mrp_list
        "mrp_control_param = ls_mrp_control_param
        mrp_stock_detail = ls_stock
        return           = ls_return.
    if ls_return-type eq 'S'.

      "Estoque = livre + em Qualidade + bloqueado +  Saldo em fornecedor-> conforme CKM3n/MB5B
      re_stock = ls_stock-unrestricted_stck + ls_stock-qual_inspection + ls_stock-blkd_stkc + ls_stock-val_stock.
    else.
      "se ocorreu erro ao ler estoque pela função calcula pela tabela

      select sum( stock_qty ) as stock into re_stock
        from matdoc
         where matnr = lv_matnr
         and werks = i_werks
         and lbbsa_sid in ( '01','02','07' ).

    endif.

  endmethod.
ENDCLASS.
