(function() {
  Danbooru.PostAppeal = {};
  
  Danbooru.PostAppeal.initialize_all = function() {
    this.initialize_appeal();
    this.hide_or_show_appeal_link();
  }
  
  Danbooru.PostAppeal.hide_or_show_appeal_link = function() {
    if (Danbooru.meta("post-is-deleted") != "true") {
      $("a#appeal").hide();
    }
  }
  
  Danbooru.PostAppeal.initialize_appeal = function() {
    $("#appeal-dialog").dialog({
      autoOpen: false, 
      width: 700,
      modal: true,
      buttons: {
        "Submit": function() {
          $("#appeal-dialog form").submit();
          $(this).dialog("close");
        },
        "Cancel": function() {
          $(this).dialog("close");
        }
      }
    });

    $("a#appeal").click(function(e) {
      e.preventDefault();
      $("#appeal-dialog").dialog("open");
    });
  }
})();

$(document).ready(function() {
  Danbooru.PostAppeal.initialize_all();
});