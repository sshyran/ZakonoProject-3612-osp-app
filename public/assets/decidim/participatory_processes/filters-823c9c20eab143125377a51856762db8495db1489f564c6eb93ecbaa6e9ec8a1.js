"use strict";$(function(){var i,s,r,t;i=window,s=$("#processes-grid"),r=s.find(".loading"),t=".order-by__tabs a",r.hide(),s.on("click",t,function(a){var e=$(a.target),d=s.find(".card-grid .column");$(t).removeClass("is-active"),e.addClass("is-active"),d.hide(),r.show(),i.history&&i.history.pushState(null,null,e.attr("href"))})});