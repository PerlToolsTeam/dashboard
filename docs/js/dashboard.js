$(document).ready(function()
{
    $(".backup_picture").on("error", function(){
        $(this).attr('src', '/images/missing_image.png');
    });

    $('#sort_table').DataTable({
      "paging": true,
      "columnDefs": [
        { "targets": [0, 3], "orderable": true },
        { "targets": "_all", "orderable": false },
      ],
      "order": [[ column, direction ]]
    });
});
