"use strict";$("#result_decidim_accountability_status_id").change(function(){var e=$(this).find(":selected").data("progress");(e||0===e)&&$("#result_progress").val(e)}),$(function(){$(document).on("open.zf.reveal","#data_picker-modal",function(){var e=null;$("#data_picker-autocomplete").autoComplete({minChars:2,source:function(t,a){try{e.abort()}catch(r){e=null}var o=$("#proposal-picker-choose").attr("href");e=$.getJSON(o,{term:t},function(e){a(e)})},renderItem:function(e,t){var a=t.replace(/[-/\\^$*+?.()|[\]{}]/g,"\\$&"),o=new RegExp("("+a.split(" ").join("|")+")","gi"),r=e[0],c=e[1];return'<div class="autocomplete-suggestion" data-model-id="'+c+'" data-val ="'+r+'">'+("#"+c+"- "+r).replace(o,"<b>$1</b>")+"</div>"},onSelect:function(e,t,a){var o=$("#proposal-picker-choose"),r=a.data("modelId"),c="#"+r+"- "+a.data("val");o.data("picker-value",r),o.data("picker-text",c),o.data("picker-choose","")}})})});