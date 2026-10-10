$(document).ready(function()
{
    $(".backup_picture").on("error", function(){
        $(this).attr('src', '/images/missing_image.png');
    });

    // See https://datatables.net/ for how this works

    var table = $('#sort_table');
    if (table.length) {
      var settings = window.dashboardSort || { column: 'name', direction: 'asc' };
      var columns = table.find('thead th');
      var orderable = [];
      var sortIndex = 0;
      columns.each(function(index) {
        var name = $(this).attr('data-sort-name');
        if (name) {
          orderable.push(index);
          if (name === settings.column) sortIndex = index;
        }
      });
      table.DataTable({
        "paging": true,
        "columnDefs": [
          { "targets": orderable, "orderable": true },
          { "targets": "_all", "orderable": false },
        ],
        "order": [[ sortIndex, settings.direction ]]
      });
    }
});
