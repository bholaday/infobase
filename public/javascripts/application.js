function changeImages() {
  if (document.images) {
    for (var i=0; i<changeImages.arguments.length; i+=2) {
      document[changeImages.arguments[i]].src = changeImages.arguments[i+1];
    }
  }
} 

$(function () {
  $('#search_type').bind('change', function() { window.location.pathname = $(this).val() });
});