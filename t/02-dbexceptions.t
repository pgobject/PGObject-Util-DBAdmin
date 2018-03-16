use warnings;
use strict;
use Test::More;
use File::Temp;
use PGObject::Util::DBAdmin;
use Test::Exception;

plan skip_all => 'DB_TESTING not set' unless $ENV{DB_TESTING};
plan tests => 17;

my $db = PGObject::Util::DBAdmin->new(
   username => 'postgres'        ,
   host     => 'localhost'       ,
   port     => '5432'            ,
   dbname   => 'pgobject_test_db',
);

eval { $db->drop };

lives_ok { $db->create } 'Create db, none exists';
dies_ok { $db->create } 'create db, already exists';
dies_ok { $db->run_file(file => 't/data/does_not_exist.sql') }
        'bad file input for run_file';

# try to load with invalid sql
my $stdout_log = File::Temp->new->filename;
my $stderr_log = File::Temp->new->filename;
dies_ok{
    $db->run_file(
        file => 't/data/bad.sql',
        stdout_log => $stdout_log,
        errlog => $stderr_log,
    ) 
} 'run_file dies with bad sql';
ok(-f $stdout_log, 'run_file stdout_log file written');
ok(-f $stderr_log, 'run_file errlog file written');
ok(defined $db->stdout, 'after run_file stdout property is defined');
ok(defined $db->stderr, 'after run_file stderr property is defined');
cmp_ok(-s $stdout_log, '==', 0, 'run_file stdout_log file has size == 0 for invalid sql');
cmp_ok(-s $stderr_log, '>', 0, 'run_file errlog file has size > 0 for invalid sql');
cmp_ok(length $db->stdout, '==', 0, 'after run_file, stdout property has length == 0 for invalid sql');
cmp_ok(length $db->stderr, '>', 0, 'after run_file, stderr property has length > 0 for invalid sql');
unlink $stdout_log;
unlink $stderr_log;

lives_ok { $db->drop } 'drop db first time, successful';
dies_ok { $db->drop } 'dropdb second time, dies';

my $backup_file = File::Temp->new->filename;
dies_ok { $db->backup(format => 'c', file => $backup_file) } 'cannot back up non-existent db';
unlink $backup_file;

dies_ok { $db->restore(format => 'c', file => 't/data/backup.sqlc') } 'cannot restore to non-existent db';

$db = PGObject::Util::DBAdmin->new(
   username => 'postgres'        ,
   host     => 'localhost'       ,
   port     => '2'            ,
   dbname   => 'pgobject_test_db',
);

dies_ok { $db->connect } 'Could not connect';
