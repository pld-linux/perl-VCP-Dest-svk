package VCP::Dest::svk ;

=head1 NAME

VCP::Dest::svk - svk destination driver

=head1 SYNOPSIS

   vcp <source> svk:/path/to/repos:path
   vcp <source> svk:/path/to/repos:path --init-repos
   vcp <source> svk:/path/to/repos:path --init-repos --delete-repos

=head1 DESCRIPTION

This driver allows L<vcp|vcp> to insert revisions in to a SVN
repository via the svk interface.

=head1 OPTIONS

=over

=item --init-repos

Initializes a SVN repository in the directory indicated.
Refuses to init a non-empty directory.

=item --delete-repos

If C<--init-repos> is passed and the target directory is not empty, it
will be deleted.  THIS IS DANGEROUS AND SHOULD ONLY BE USED IN TEST
ENVIRONMENTS.

=back

=cut
ues strict;
our $VERSION = '0.20' ;
our @ISA = qw( VCP::Dest );

use SVN::Core;
use SVN::Repos;
use SVK;
use SVK::XD;
use SVK::Util qw( md5 );
use Data::Hierarchy;
use VCP::Logger qw( pr lg pr_doing pr_did );
use VCP::Rev ('iso8601format');
use VCP::Utils qw( empty is_win32 escape_filename);
use File::Path ;
use VCP::Debug ':debug' ;

use vars qw( $debug ) ;

$debug = 0 ;

sub _db_store_location {
   my $self = shift ;

   my $loc = $self->{SVK_REPOSPATH};

   return File::Spec->catdir( $loc, 'vcp_state',
			      escape_filename ($self->{SVK_TARGETPATH}), @_ );
}

sub new {
   my $self = shift->SUPER::new( @_ ) ;

   ## Parse the options
   my ( $spec, $options ) = @_ ;

   $self->parse_repo_spec( $spec )
      unless empty $spec;

   $self->parse_options( $options );

   return $self ;
}

sub parse_svk_depot_spec {

}

sub options_spec {
   my $self = shift;
   return (
      $self->SUPER::options_spec,
      "init-repos"     => \$self->{SVK_INIT_REPOS},
      "delete-repos"   => \$self->{SVK_DELETE_REPOS},
      "nolayout"       => \$self->{SVK_NOLAYOUT},
      "trunk-dir=s"    => \$self->{SVK_TRUNK_DIR},
      "branch-dir=s"   => \$self->{SVK_BRANCH_DIR},
   );
}

sub init_repos {
    my $self = shift;

    $self->{SVK_REPOS} = SVN::Repos::create ($self->{SVK_REPOSPATH},  undef, undef, undef,
					     {'bdb-txn-nosync' => '1',
					      'bdb-log-autoremove' => '1'});
}

sub init_layout {
    my $self = shift;
    my $fs = $self->{SVK_REPOS}->fs;
    my $root = $fs->revision_root ($fs->youngest_rev);

    my ($trunk, $branch) = @{$self}{qw/SVK_TRUNKPATH SVK_BRANCHPATH/};
    return unless $root->check_path ($trunk) == $SVN::Node::none ||
	$root->check_path ($branch) == $SVN::Node::none;

    my $editor = [$self->{SVK_REPOS}->get_commit_editor ('',
							 '',
							 'VCP', 'VCP: initializing layout',
							 undef)];
    my $edit = SVN::Simple::Edit->new
	( _editor => $editor,
	  missing_handler =>
	  &SVN::Simple::Edit::check_missing ($root)
	);

    $edit->open_root (0);
    $edit->add_directory ($branch);
    $edit->add_directory ($trunk) if $trunk ne $branch;
    $edit->close_edit ();
}

sub init {
   my $self = shift;

   $self->{SVK_REPOSPATH} = $self->repo_server;
   $self->{SVK_TARGETPATH} = $self->repo_filespec;

   ## Set default repo_id.
   $self->repo_id( "svk:" . $self->repo_server )
      if empty $self->repo_id && ! empty $self->repo_server ;

#   $self->deduce_rev_root( $self->repo_filespec ) ;

   $self->{SVK_TRUNK_DIR} ||= 'trunk';
   $self->{SVK_BRANCH_DIR} = 'branches'
       unless defined $self->{SVK_BRANCH_DIR};

   if ( $self->{SVK_INIT_REPOS} ) {
      if ( $self->{SVK_DELETE_REPOS} ) {
         $self->rev_map->delete_db;
         $self->head_revs->delete_db;
	 rmtree [ $self->{SVK_REPOSPATH} ];
      }
      $self->init_repos;
   }
   else {
      pr "ignoring --delete-repos, which is only useful with --init-repos"
         if $self->{SVK_DELETE_REPOS};
      $self->{SVK_REPOS} ||= SVN::Repos::open ($self->{SVK_REPOSPATH});
   }
   $self->{SVK_TRUNKPATH} = $self->{SVK_NOLAYOUT} ? $self->{SVK_TARGETPATH} :
       ($self->{SVK_TARGETPATH} eq '/' ? '/' : $self->{SVK_TARGETPATH}.'/').
	   $self->{SVK_TRUNK_DIR};

   unless ($self->{SVK_NOLAYOUT}) {
       $self->{SVK_BRANCHPATH} = $self->{SVK_TARGETPATH} eq '/' ? '/' : $self->{SVK_TARGETPATH}.'/';
       if ($self->{SVK_BRANCH_DIR} eq '.') {
	   chop $self->{SVK_BRANCHPATH};
       }
       else {
	   $self->{SVK_BRANCHPATH} .= $self->{SVK_BRANCH_DIR};
       }
       $self->init_layout;
   }

   $self->{SVK} = SVK->new ( output => \$self->{SVK_OUTPUT},
			     xd => SVK::XD->new
			     ( depotmap => {'' => $self->{SVK_REPOSPATH}},
			       checkout => Data::Hierarchy->new ));

   my $coroot = $self->work_path ("co");
   $self->mkpdir ($coroot);
#   $self->{SVK}->checkout ('//', $coroot);

   $self->rev_map->open_db;
   $self->head_revs->open_db;
}

sub compare_base_revs {
   my $self = shift ;
   my ( $r, $source_path ) = @_ ;

   die "\$source_path not set at ", caller
      unless defined $source_path;

   open FH, '<', $source_path or die "$!: $source_path" ;
   my $source_digest = md5( \*FH ) ;

   my ($prefix, $name, $rev ) =
       $self->rev_map->get ( [ $r->source_repo_id, $r->id ] );
   my $dest_digest = $self->{SVK_REPOS}->fs->revision_root ($rev)->
       file_md5_checksum ("$prefix/$name");

   lg "$r checking out ", $r->as_string, "as $prefix/$name\@$rev from svk dest repo";

   die( "vcp: base revision\n",
       $rev->as_string, "\n",
       "differs from the last version in the destination p4 repository.\n",
       "    source digest: $source_digest (in ", $source_path, ")\n",
       "    dest. digest:  $dest_digest (in $prefix/$name\@$rev)\n"
   ) unless $source_digest eq $dest_digest ;
}

sub handle_header {
   my $self = shift ;
   my ( $h ) = @_;

   $self->{SVK_PENDING}         = [] ;
   $self->{SVK_PREV_COMMENT}    = undef ;
   $self->{SVK_PREV_CHANGE_ID}  = undef ;
   $self->{SVK_COMMIT_COUNT}    = 0 ;

   $self->SUPER::handle_header( @_ ) ;
}

sub handle_rev {
   my $self = shift ;
   my $r ;
   ( $r ) = @_ ;

   debug "got ", $r->as_string if debugging;
   my $change_id = $r->change_id;

   $self->commit
      if @{$self->{SVK_PENDING}}
         && $change_id ne $self->{SVK_PREV_CHANGE_ID};

   $self->{SVK_PREV_CHANGE_ID} = $change_id;
   $self->{SVK_PREV_COMMENT}   = $r->comment;

   if ( $r->is_base_rev ) {
      my $work_path = $r->get_source_file;
      $self->compare_base_revs( $r, $work_path );
      pr_doing;
      return;
   }

   push @{$self->{SVK_PENDING}}, $r;
}

sub handle_footer {
   my $self = shift ;

   $self->commit if @{$self->{SVK_PENDING}};

   $self->SUPER::handle_footer ;

   pr "committed ", $self->{SVK_COMMIT_COUNT}, " revisions";
}

sub update_revision_prop {
    my ($self, $rev, $r) = @_;
    my $fs = $self->{SVK_REPOS}->fs;
    my $pool = SVN::Pool->new_default;
    if ($r->time) {
	my $time = iso8601format($r->time);
	$time =~ s/\s/T/;
	$time =~ s/Z/\.00000Z/;
	$fs->change_rev_prop($rev, 'svn:date', $time);
    }
    $fs->change_rev_prop($rev, 'svn:author', $r->user_id || 'unknown_user');

    $self->{SVK_COMMIT_CALLBACK}->($rev, $r->source_change_id)
	if $r->source_change_id && $self->{SVK_COMMIT_CALLBACK};
}

sub commit {
    my $self = shift;
    my $revs = $self->{SVK_PENDING};
    $self->{SVK_PENDING} = [];
    my $fs = $self->{SVK_REPOS}->fs;
    my $pool = SVN::Pool->new_default;
    my $root = $fs->revision_root ($fs->youngest_rev);
    my $branch = $revs->[0]->branch_id || '';
    my $coroot = $self->work_path ("co");

    $self->{SVK}->checkout ("/$self->{SVK_TRUNKPATH}", $coroot)
	unless -d $coroot;

    unless ($self->{SVK_NOLAYOUT} || defined $self->{SVK_TRUNK}) {
	unless (defined ($self->{SVK_TRUNK} = $root->node_prop
			 ($self->{SVK_TRUNKPATH}, 'vcp:trunk'))) {
	    $self->{SVK}->propset ('--direct', '-m', "[vcp] select <$branch> as trunk",
				   'vcp:trunk', $branch, "/$self->{SVK_TRUNKPATH}");
	    $self->{SVK_TRUNK} = $branch;
	}
    }

    my $thisbranch = ($self->{SVK_NOLAYOUT} || $branch eq $self->{SVK_TRUNK})
	? "/$self->{SVK_TRUNKPATH}" : "/$self->{SVK_BRANCHPATH}/$branch";

    if ($root->check_path ($thisbranch) == $SVN::Node::none) {
	$self->handle_branchpoint ($branch, $revs);
    }
    else {
	if ($self->{SVK_LAST_BRANCH} && $thisbranch ne $self->{SVK_LAST_BRANCH}) {
	    $self->{SVK}->switch ($thisbranch, $coroot);
	    die "$self->{SVK_OUTPUT}"
		if $self->{SVK_OUTPUT} =~ m/skip/;
	}
	$self->{SVK_LAST_BRANCH} = $thisbranch;

	$self->handle_branching ($thisbranch, $revs);
	$self->prepare_commit ($thisbranch, $revs);

	$self->{SVK}->import ('--direct', '--force',
			      '-m', $revs->[0]->comment || '** no comments **',
			      $thisbranch, $self->work_path ("co"));
	debug "import result:\n$self->{SVK_OUTPUT}" if debugging;
	$self->{SVK}->update ($self->work_path ("co"));
	$self->{SVK}->status ($self->work_path ("co"));
	die "not identical after import to $thisbranch: $self->{SVK_OUTPUT}"
	    if $self->{SVK_OUTPUT};
    }

    my $rev = $fs->youngest_rev;
    $self->update_revision_prop ($rev, $revs->[0]);

    pr_did "revision", $rev;
    ++$self->{SVK_COMMIT_COUNT};
    for my $r (@$revs) {
	pr_doing;
	$self->rev_map->set
	    ( [ $r->source_repo_id, $r->id ],
	      $thisbranch, $r->name, $rev );

	$self->head_revs->set
	    ( [ $r->source_repo_id, $r->source_filebranch_id ],
	      $r->source_rev_id
	    );
     }
}

sub deduce_branchparent {
    my ($self, $revs) = @_;
    my $branchinfo;
    for my $r (@$revs) {
	my $pr_id = $r->previous_id;
	die "branchpoint has something without previous" if empty $pr_id;

	my ( $pprefix, $pname, $prev ) =
	     $self->rev_map->get( [ $r->source_repo_id, $pr_id ] );

	$branchinfo->{$pprefix} = $prev
	    if !$branchinfo->{$pprefix} || $prev > $branchinfo->{$pprefix};
    }

    if (keys %$branchinfo != 1) {
	die "complicated branchpoint not handled yet";
    }
    for my $path (keys %$branchinfo) {
	my $rev = $branchinfo->{$path};
	# XXX: verify the latest rev is still in range for all revs
	return ([$path, $rev, $revs]);
    }

    return ([undef, undef, $revs]);
}

sub handle_branchpoint {
    my ($self, $branch, $revs) = @_;
    my $coroot = $self->work_path ("co");
    my (@branchfrom) = $self->deduce_branchparent ($revs);
    my $work_path = $self->work_path ('branch');
    for (@branchfrom) {
	my ($branchfrom, $branchfromrev, $branchrevs) = @$_;
	unless (-e $work_path) {
	    $self->{SVK}->checkout ('-N', "/$self->{SVK_BRANCHPATH}", $work_path);
	    die if -d "$work_path/$branch";
	    $self->{SVK}->copy ('-r', $branchfromrev, $branchfrom, "$work_path/$branch");
	    debug "copy result:\n$self->{SVK_OUTPUT}" if debugging;
	    # do fixup for things not in $branchrevs
	    my %copied;
	    $copied{$_->name}++ for @$branchrevs;
	    debug "files belong to this copy: ".join(',',keys %copied) if debugging;
	    for (split /\n/, $self->{SVK_OUTPUT}) {
		my (undef, $path) = split /\s+/;
		next if -d $path;
		my $npath = $path;
		$npath =~ s|^\Q$work_path/$branch\E/?||;
		next if exists $copied{$npath};
		debug "remove: $path" if debugging;
		$self->{SVK}->delete ($path) if -e $path;
	    }
	    rename ($coroot, "$coroot.backup");
	    symlink ("$work_path/$branch", $coroot);
	}
	else {
	    # copy $branchrevs from $branch{from,rev} to co
	    die "complicated branching at a batch not implemented yet";
	    $self->handle_branching ("$self->{SVK_BRNACHPATH}/$branch", $branchrevs);
	}
	$self->prepare_commit ("$self->{SVK_BRANCHPATH}/$branch", $branchrevs);
    }
    $self->{SVK}->status ($coroot);
    $self->{SVK}->commit ('--direct', '-m', $revs->[0]->comment || 'bzz', $self->work_path ('branch'));
    unlink ($coroot);
    rmtree [$work_path];
    rename ("$coroot.backup", $coroot);
}

sub prepare_commit {
    my ($self, $prefix, $revs) = @_;

    for my $r (@$revs) {
	next if $r->is_placeholder_rev;
	my $work_path = $self->work_path( "co", $r->name ) ;
	unlink $work_path if -e $work_path;

	if ($r->action eq 'add' || $r->action eq 'edit' ) {
	    my $source_fn = $r->get_source_file;
	    $self->mkpdir( $work_path );
	    link $source_fn, $work_path
		or die "$! linking '$source_fn' -> '$work_path'" ;
	}
    }
}

sub handle_branching {
    my ($self, $prefix, $revs) = @_;
    for my $r (@$revs) {
	my $pr_id = $r->previous_id;
	next if empty $pr_id;
	my $fn = $r->name ;
	my $work_path = $self->work_path( "co", $fn ) ;

	my ( $pprefix, $pname, $prev ) = eval {
	     $self->rev_map->get( [ $r->source_repo_id, $pr_id ] ) };
	if ($@) {
	    pr "abandon branch source $pr_id for ".$r->as_string;
	    $r->action ('add');
	    undef $@;
	    next;
	}
	next if $pprefix eq $prefix;

	my $dir = $self->mkpdir ($work_path);
	$self->{SVK}->add ($dir);
	$self->{SVK}->copy ('-r', $prev, "$pprefix/$pname", $work_path);
#	pr "copy from $pprefix/$pname -> $work_path ($prefix)";
    }
}

sub sort_filters {
    my $self = shift;
    require VCP::Filter::map;
    require VCP::Filter::stringedit;

    return ( $self->require_change_id_sort( @_ ),
	     VCP::Filter::stringedit->new
	     ( "",
	       [ "user_id,name,labels", "@",   "_at_"   ,
		 "user_id,name,labels", "#",   "_pound_",
		 "user_id,name,labels", "*",   "_star_" ,
		 "user_id,name,labels", "%",   "_pcnt_" ,
		 "branch_id", "/", "_slash_" ,
	       ],
	     ),
	   );
}


1;
