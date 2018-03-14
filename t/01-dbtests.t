use Test::More;
use Test::Exception;
use PGObject::Util::DBAdmin;
use File::Temp;

plan skip_all => 'DB_TESTING not set' unless $ENV{DB_TESTING};
plan tests => 57;

# Constructor

my $dbh;
my $db;

ok($db = PGObject::Util::DBAdmin->new(
     username => 'postgres',
     password => undef,
     dbname   => 'pgobject_test_db',
     host     => 'localhost',
     port     => '5432'
), 'Created db admin object');

# Drop db if exists

eval { $db->drop };

# Test backup_globals to auto-generated temp file
my $backup_file;
ok($backup_file = $db->backup_globals(
    tempdir => 't/var/',
), 'can backup globals');
ok(-f $backup_file, 'backup_globals output file exists');
ok($backup_file =~ m|^t/var/|, 'backup file respects tempdir parameter');
cmp_ok(-s $backup_file, '>', 0, 'backup_globals output file has size > 0');
unlink $backup_file;

# Test backup_globals to specified file
$backup_file = File::Temp->new->filename;
ok($backup_file = $db->backup_globals(
    file => $backup_file,
), 'can backup globals to specified file');
ok(-f $backup_file, 'specified backup_globals output file exists');
cmp_ok(-s $backup_file, '>', 0, 'specified backup_globals output file has size > 0');
undef $backup_file;


# List dbs
my @dblist;

ok(@dblist = $db->list_dbs, 'Got a db list');

ok (!grep {$_ eq 'pgobject_test_db'} @dblist, 'DB list does not contain pgobject_test_db');

# Create db

$db->create;

ok($db->server_version, 'Got a server version');

ok (grep {$_ eq 'pgobject_test_db'} $db->list_dbs, 'DB list does contain pgobject_test_db after create call');

# load with schema

ok ($db->run_file(file => 't/data/schema.sql'), 'Loaded schema');

ok ($dbh = $db->connect, 'Got dbi handle');

my ($foo) = @{ $dbh->selectall_arrayref('select count(*) from test_data') };
is ($foo->[0], 1, 'Correct count of data') ;

$dbh->disconnect;

# backup/drop/create/restore, formats undef, p, and c
foreach my $format ((undef, 'p', 'c')) {
    my $display_format = $format || 'undef';

    my $backup;
    ok($backup = $db->backup(
           format => $format,
           tempdir => 't/var/',
       ), "Made backup, format $display_format");
    ok($backup =~ m|^t/var/|, 'backup file respects tempdir parameter');
    ok(-f $backup, "backup format $display_format output file exists");
    cmp_ok(-s $backup, '>', 0, "backup format $display_format output file has size > 0");

    ok($db->drop, "dropped db, format $display_format");
    ok (!(grep{$_ eq 'pgobject_test_db'} @dblist), 
           'DB list does not contain pgobject_test_db');

    dies_ok {
        $db->restore(
            format => $format,
            file   => 't/data/does-not-exist',
        )
    } "die when restore file does not exist, format $display_format";

    ok($db->create, "created db, format $display_format");
    ok($dbh = $db->connect, "Got dbi handle, format $display_format");
    ok($db->restore(
          format => $format,
          file   => $backup,
       ), "Restored backup, format $display_format");
    ok(defined $db->stderr, 'stderr captured during restore');
    ok(defined $db->stdout, 'stdout captured during restore');
    ok(($foo) = $dbh->selectall_arrayref('select count(*) from test_data'),
               "Got results from test data count, format $display_format");
    is($foo->[0]->[0], 1, "correct data count, format $display_format");
    $dbh->disconnect;
    unlink $backup;
}
