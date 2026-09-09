// This file is the application's JavaScript manifest.
//= require jquery
//= require jquery_ujs
//= require turbolinks
//= require_tree .

function stripLeakedInvoiceStyles(nextBody){
  var incoming = nextBody || document.body;
  if(incoming && incoming.classList.contains('invoice-doc')) return;
  document.querySelectorAll('style[data-invoice-sheet]').forEach(function(el){ el.remove(); });
}

function initAppUI(){
  var btn = document.querySelector('.nav-toggle');
  if(btn){
    // guard: don't attach duplicate handlers
    if(!btn.__navBound){
      btn.addEventListener('click', function(){
        var menu = document.querySelector('.nav-menu');
        if(menu) menu.classList.toggle('show');
      });
      btn.__navBound = true;
    }
  }
}

// Init on DOMContentLoaded for non-Turbolinks loads
document.addEventListener('DOMContentLoaded', function(){
  stripLeakedInvoiceStyles();
  initAppUI();
});

// Also init on Turbolinks page loads if Turbolinks is present
document.addEventListener('turbolinks:before-render', function(event){
  stripLeakedInvoiceStyles(event.data && event.data.newBody);
});
document.addEventListener('turbolinks:load', function(){
  stripLeakedInvoiceStyles();
  initAppUI();
});
