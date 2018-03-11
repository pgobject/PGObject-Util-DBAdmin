use Test::More;
use PGObject::Util::DBAdmin;
use Test::Exception;

plan tests => 4;

# These tests do not require a working database connection
my $db = PGObject::Util::DBAdmin->new(
   username => 'postgres'        ,
   host     => 'localhost'       ,
   port     => '5432'            ,
   dbname   => 'pgobject_test_db',
);

dies_ok {
    $db->backup(
        tempdir => 'This_directory_does_not_exist'
    )
} 'backup db with non-existent tempdir';

dies_ok {
    $db->backup(
        format => 'THIS_IS_A_BAD_FORMAT'
    )
} 'backup db with bad format';

dies_ok {
    $db->backup(
        file => 't/data/an_existing_file'
    )
} 'backup db would overwrite an existing file';

dies_ok {
    $db->backup(
        tempdir => 't/data/an_existing_file'
    )
} 'backup db tempdir is an existing file';
