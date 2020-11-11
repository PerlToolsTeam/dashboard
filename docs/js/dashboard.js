$(document).ready(function()
{
    $(".backup_picture").on("error", function(){
        $(this).attr('src', '/images/missing_image.png');
    });

    $('#sort_table').DataTable({
      "paging": false,
      "columnDefs": [
        { "targets": [0, 2], "orderable": true },
        { "targets": "_all", "orderable": false },
      ]
    });
});
