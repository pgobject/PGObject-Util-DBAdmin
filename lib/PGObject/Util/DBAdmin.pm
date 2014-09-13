package PGObject::Util::DBAdmin;

use 5.008;
use strict;
use warnings FATAL => 'all';

use Carp;
use Moo;
use DBI;
use File::Temp;
use Capture::Tiny ':all';

=head1 NAME

PGObject::Util::DBAdmin - PostgreSQL Database Management Facilities for 
PGObject

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';


=head1 SYNOPSIS

This module provides an interface to the basic Postgres db manipulation 
utilities.

 my $db = PGObject::Util::DBAdmin->new(
    username => 'postgres', 
    password => 'mypassword',
    host     => 'localhost',
    port     => '5432',
    dbname   => 'mydb'
 );

 my @dbnames = $db->list_dbs(); # like psql -l

 $db->create(); # createdb
 $db->run_file(file => 'sql/initial_schema.sql'); # psql -f

 my $filename = $db->backup(format => 'c'); # pg_dump -Fc

 my $db2 = PGObject::Util::DBAdmin->new($db->export, (dbname => 'otherdb'));

=head1 PROPERTIES

=head2 username

=cut 

has username => (is => 'ro');

=head2 password

=cut 

has password => (is => 'ro');

=head2 host

In PostgreSQL, this can refer to the hostname or the absolute path to the 
directory where the UNIX sockets are set up.

=cut 

has host => (is => 'ro');

=head2 port

Default '5432'

=cut 

has port => (is => 'ro');

=head2 dbname

=cut 

has dbname => (is => 'ro');

=head1 SUBROUTINES/METHODS

=head2 new

Creates a new db admin object for manipulating databases.

=head2 export

Exports the database parameters in a hash so it can be used to create another
pbject.

=cut

sub export {
    my $self = shift;
    return map {$_ => $self->$_() } qw(username password host port dbname)
}

=head2 connect

Connects to the db using DBI and returns a db connection

=cut

sub connect {
    my $self = shift;
    return DBI->connect('dbi:Pg:dbname=' . $self->dbname, 
                           $self->username, $self->password);
}

=head2 list_dbs

Returns a list of db names.

=cut

sub list_dbs {
    my $self = shift;

    return map { $_->[0] } 
           @{ __PACKAGE__->new($self->export, (dbname => 'template1')
           )->connect->selectall_arrayref(
                 'SELECT datname from pg_database order by datname'
           ) };
}

=head2 create

Creates a new db.  Dies if there is an error.

Supported arguments:

=over

=item copy_of

Creates the db as a copy of the one of that name.  Default is unspecified.

=back

=cut

sub create {
    my $self = shift;
    my %args = @_;

    local $ENV{PGPASSWORD} = $self->password if $self->password;
    my $command = "createdb "
                  . join (' ', (
                       $self->username ? "-U " . $self->username . ' ' : '' ,
                       $args{copy_of} ? "-T $args{copy_of} " : ''           ,
                       $self->dbname)
                  );
    my $stderr = capture_stderr sub{ `$command` };
    die $stderr if $stderr;
    return 1;
}

=head2 run_file

Run the specified file on the db.  Accepted parameters are:

=over

=item file

Path to file to be run

=item log

Path to combined stderr/stdout log.  If specified, do not specify other logs
as this is unsupported.

=item errlog 

Path to error log to store stderr output

=item stdout_log


Path to where to log standard outut

=item continue_on_error

If set, does not die on error.

=back

=cut

sub run_file {
    my ($self, %args) = @_;
    croak 'Must specify file' unless $args{file};
    local $ENV{PGPASSWORD} = $self->password if $self->password;
    my $log = '';
    my $errlog = 0;
    if ($args{log}){
       $log = qq( 1>&2 );
       $errlog = 1;
       open(ERRLOG, '>>', $args{log})
    } else {
       if ($args{stdout_log}){
          $log .= qq(>> "$args{stdout_log}" );
       }
       if ($args{errlog}){
          $errlog = 1;
          open(ERRLOG, '>>', $args{errlog})
       }
    }
    my $command = qq(psql -f "$args{file}" )
                  . join(' ', 
                       ($self->username ? "-U " . $self->username . ' ' : '',
                        $self->dbname ? $self->dbname : ' ' ,
                        $log)
                  );
    my $stderr = capture_stderr sub{ `$command` || die "ERROR: $!" };
    print STDERR $stderr;
    print ERRLOG $stderr if $errlog;
    close ERRLOG if $errlog;
    for my $err (split /\n/, $stderr) {
          die $err if $err =~ /(ERROR|FATAL)/;
    }
    return 1;
}

=head2 backup

Takes a backup and delivers the temporary file name to the handler.

Accepted parameters include:

=over

=item format

The specified format, for example c for custom.  Defaults to plain text

=item tempdir

The directory to store temp files in.  Defaults to $ENV{TEMP} if set and 
'/tmp/' if not.

=back

Returns the file name of the tempfile.

=cut

sub backup {
    my ($self, %args) = @_;
    local $ENV{PGPASSWORD} = $self->password if $self->password;
    my $tempdir = $args{tempdir} || $ENV{TEMP} || '/tmp';
    $tempdir =~ s|/$||;
    
    my $tempfile = $args{file} || File::Temp->new(
                                      DIR => $tempdir, UNLINK => 0
                                  )->filename 
                                      || die "could not create temp file: $@, $!";
    my $command = 'pg_dump ' . join(" ", (
                  $self->dbname         ? "-d " . $self->dbname . " "   : '' ,
                  $self->username       ? "-U " . $self->username . ' ' : '' ,
                  defined $args{format} ? "-F$args{format} "            : '' ,
                  qq(> "$tempfile" )));
    my $stderr = capture_stderr { `$command` };
    print STDERR $stderr;
    for my $err (split /\n/, $stderr) {
          die $err if $err =~ /(ERROR|FATAL)/;
    }
    return $tempfile;
}

=head2 restore

Restores from a saved file.  Must pass in the file name as a named argument.

Recognized arguments are:

=over

=item file

Path to file

=item format

The specified format, for example c for custom.  Defaults to plain text

=item log

Path to combined stderr/stdout log.  If specified, do not specify other logs
as this is unsupported.

=item errlog 

Path to error log to store stderr output

=item stdout_log

Path to where to log standard outut

=back

=cut

sub restore {
    my ($self, %args) = @_;
    croak 'Must specify file' unless $args{file};

    return $self->run_file(%args) 
           if not defined $args{format} or $args{format} eq 'p';

    local $ENV{PGPASSWORD} = $self->password if $self->password;
    my $log = '';
    my $errlog;
    if ($args{log}){
       $log = qq( 1>&2 );
       $errlog = 1;
       open(ERRLOG, '>>', $args{log})
    } else {
       if ($args{stdout_log}){
          $log .= qq(>> "$args{stdout_log}" );
       }
       if ($args{errlog}){
          $errlog = 1;
          open(ERRLOG, '>>', $args{errlog})
       }
    }
    my $command = 'pg_restore ' . join(' ', (
                  $self->dbname         ? "-d " . $self->dbname . " "   : '' ,
                  $self->username       ? "-U " . $self->username . ' ' : '' ,
                  defined $args{format} ? "-F$args{format}"             : '' ,
                  qq("$args{file}")));
    my $stderr = capture_stderr sub{ `$command` };
    print STDERR $stderr;
    print ERRLOG $stderr if $errlog;
    close ERRLOG if $errlog;
    for my $err (split /\n/, $stderr) {
          die $err if $err =~ /(ERROR|FATAL)/;
    }
    return 1;
}

=head2 drop

Drops the database.  This is not recoverable.

=cut

sub drop {
    my ($self, %args) = @_;

    croak 'No db name of this object' unless $self->dbname;

    local $ENV{PGPASSWORD} = $self->password if $self->password;
    
    my $command = "dropdb " . join (" ", (
                  $self->username ? "-U " . $self->username . ' ' : '' ,
                  $self->dbname));
    my $stderr = capture_stderr { `$command` };
    die $stderr if $stderr =~ /(ERROR|FATAL)/;
    return 1;
}

=head1 AUTHOR

Chris Travers, C<< <chris at efficito.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-pgobject-util-dbadmin at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=PGObject-Util-DBAdmin>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PGObject::Util::DBAdmin


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=PGObject-Util-DBAdmin>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/PGObject-Util-DBAdmin>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/PGObject-Util-DBAdmin>

=item * Search CPAN

L<http://search.cpan.org/dist/PGObject-Util-DBAdmin/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2014 Chris Travers.

This program is distributed under the (Revised) BSD License:
L<http://www.opensource.org/licenses/BSD-3-Clause>

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

* Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.

* Neither the name of Chris Travers's Organization
nor the names of its contributors may be used to endorse or promote
products derived from this software without specific prior written
permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of PGObject::Util::DBAdmin
