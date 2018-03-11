use Test::More;
use PGObject::Util::DBAdmin;
use Test::Exception;

plan tests => 12;

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
        file => 't/data/an_existing_file/cannot_write'
    )
} 'backup db cannot write to specified file';

dies_ok {
    $db->backup(
        tempdir => 't/data/an_existing_file'
    )
} 'backup db tempdir is an existing file';


dies_ok {
    $db->backup_globals(
        tempdir => 'This_directory_does_not_exist'
    )
} 'backup_globals with non-existent tempdir';

dies_ok {
    $db->backup_globals(
        file => 't/data/an_existing_file/cannot_write'
    )
} 'backup_globals cannot write to specified file';

dies_ok {
    $db->backup_globals(
        tempdir => 't/data/an_existing_file'
    )
} 'backup_globals tempdir is an existing file';


throws_ok {
    $db->restore(
        file   => 't/data/an_existing_file',
        log    => 't/data/an_existing_file/cannot_write',
        format => 'c',
    )
} qr/^Cannot open specified log file for writing/,
'restore log file is unwriteable';

throws_ok {
    $db->restore(
        file   => 't/data/an_existing_file',
        errlog => 't/data/an_existing_file/cannot_write',
        format => 'c',
    )
} qr/^Cannot open specified errlog file for writing/,
'restore errlog file is unwriteable';

dies_ok {
    $db->restore(
        file   => 't/data/an_existing_file',
        format => 'AN_INVALID_FORMAT',
    )
} 'restore method called with invalid format';


throws_ok {
    $db->run_file(
        file   => 't/data/an_existing_file',
        log    => 't/data/an_existing_file/cannot_write',
    )
} qr/^Cannot open specified log file for writing/,
'run_file log file is unwriteable';

throws_ok {
    $db->run_file(
        file   => 't/data/an_existing_file',
        errlog => 't/data/an_existing_file/cannot_write',
    )
} qr/^Cannot open specified errlog file for writing/,
'run_file errlog file is unwriteable';

