# This module is part of debbugs, and is released
# under the terms of the GPL version 2, or any later version. See the
# file README and COPYING for more information.
# Copyright 2013 by Don Armstrong <don@donarmstrong.com>.

package Debbugs::DB::Load;

=head1 NAME

Debbugs::DB::Load -- Utility routines for loading the database

=head1 SYNOPSIS


=head1 DESCRIPTION


=head1 BUGS

None known.

=cut

use warnings;
use strict;
use vars qw($VERSION $DEBUG %EXPORT_TAGS @EXPORT_OK @EXPORT);
use base qw(Exporter);

BEGIN{
     ($VERSION) = q$Revision$ =~ /^Revision:\s+([^\s+])/;
     $DEBUG = 0 unless defined $DEBUG;

     @EXPORT = ();
     %EXPORT_TAGS = (load_bug    => [qw(load_bug handle_load_bug_queue load_bug_log)],
		     load_debinfo => [qw(load_debinfo)],
		     load_package => [qw(load_package)],
		     load_suite => [qw(load_suite)],
		    );
     @EXPORT_OK = ();
     Exporter::export_ok_tags(keys %EXPORT_TAGS);
     $EXPORT_TAGS{all} = [@EXPORT_OK];
}

use Params::Validate qw(validate_with :types);

use Debbugs::Status qw(read_bug split_status_fields);
use Debbugs::DB;
use DateTime;
use Debbugs::Common qw(make_list getparsedaddrs);
use Debbugs::Config qw(:config);
use Carp;

=head2 Bug loading

Routines to load bug; exported with :load_bug

=over

=item load_bug

     load_bug(db => $schema,
              data => split_status_fields($data),
              tags => \%tags,
              queue => \%queue);

Loads a bug's metadata into the database. (Does not load any messages)

=over

=item db -- Debbugs::DB object

=item data -- Bug data (from read_bug) which has been split with split_status_fields

=item tags -- tag cache (hashref); optional

=item queue -- queue of operations to perform after bug is loaded; optional.

=back

=cut

sub load_bug {
    my %param = validate_with(params => \@_,
                              spec => {db => {type => OBJECT,
                                             },
                                       data => {type => HASHREF,
                                                optional => 1,
                                               },
                                       bug => {type => SCALAR,
                                               optional => 1,
                                              },
                                       tags => {type => HASHREF,
                                                default => sub {return {}},
                                                optional => 1},
                                       severities => {type => HASHREF,
                                                      default => sub {return {}},
                                                      optional => 1,
                                                     },
                                       queue => {type => HASHREF,
                                                 optional => 1},
                                      });
    my $s = $param{db};
    if (not exists $param{data} and not exists $param{bug}) {
        croak "One of data or bug must be provided to load_bug";
    }
    if (not exists $param{data}) {
        $param{data} = read_bug(bug => $param{bug});
    }
    my $data = $param{data};
    my $tags = $param{tags};
    my $queue = $param{queue};
    my $severities = $param{severities};
    my $can_queue = 1;
    if (not defined $queue) {
        $can_queue = 0;
        $queue = {};
    }
    my %tags;
    my $s_data = split_status_fields($data);
    for my $tag (make_list($s_data->{keywords})) {
	next unless defined $tag and length $tag;
	# this allows for invalid tags. But we'll use this to try to
	# find those bugs and clean them up
	if (not exists $tags->{$tag}) {
	    $tags->{$tag} = $s->resultset('Tag')->
            find_or_create({tag => $tag});
	}
	$tags{$tag} = $tags->{$tag};
    }
    my $severity = length($data->{severity}) ? $data->{severity} : $config{default_severity};
    if (exists $severities->{$severity}) {
        $severity = $severities->{$severity};
    } else {
        $severity = $s->resultset('Severity')->
            find_or_create({severity => $severity});
    }
    my $bug =
        {id => $data->{bug_num},
         creation => DateTime->from_epoch(epoch => $data->{date}),
         log_modified => DateTime->from_epoch(epoch => $data->{log_modified}),
         last_modified => DateTime->from_epoch(epoch => $data->{last_modified}),
         archived => $data->{archived},
         (defined $data->{unarchived} and length($data->{unarchived}))?(unarchived => DateTime->from_epoch(epoch => $data->{unarchived})):(),
         forwarded => $data->{forwarded} // '',
         summary => $data->{summary} // '',
         outlook => $data->{outlook} // '',
         subject => $data->{subject} // '',
         done_full => $data->{done} // '',
         severity => $severity,
         owner_full => $data->{owner} // '',
         submitter_full => $data->{originator} // '',
        };
    my %addr_map =
        (done => 'done',
         owner => 'owner',
         submitter => 'originator',
        );
    for my $addr_type (keys %addr_map) {
        my @addrs = getparsedaddrs($data->{$addr_map{$addr_type}} // '');
        next unless @addrs;
        $bug->{$addr_type} = $s->resultset('Correspondent')->find_or_create({addr => lc($addrs[0]->address())});
        # insert the full name as well
        my $full_name = $addrs[0]->phrase();
        $full_name =~ s/^\"|\"$//g;
        $full_name =~ s/^\s+|\s+$//g;
        if (length $full_name) {
            $bug->{$addr_type}->
                update_or_create_related('correspondent_full_names',
                                        {full_name=>$full_name,
                                         last_seen => 'NOW()'});
        }
    }
    my $b = $s->resultset('Bug')->update_or_create($bug) or
        die "Unable to update or create bug $bug->{id}";
     $s->txn_do(sub {
		   for my $ff (qw(found fixed)) {
		       my @elements = $s->resultset('BugVer')->search({bug => $data->{bug_num},
								       found  => $ff eq 'found'?1:0,
								      });
		       my %elements_to_delete = map {($elements[$_]->ver_string(),$elements[$_])} 0..$#elements;
		       my %elements_to_add;
                       my @elements_to_keep;
		       for my $version (@{$data->{"${ff}_versions"}}) {
			   if (exists $elements_to_delete{$version}) {
			       push @elements_to_keep,$version;
			   } else {
			       $elements_to_add{$version} = 1;
			   }
		       }
                       for my $version (@elements_to_keep) {
                           delete $elements_to_delete{$version};
                       }
		       for my $element (keys %elements_to_delete) {
                           $elements_to_delete{$element}->delete();
		       }
		       for my $element (keys %elements_to_add) {
			   # find source package and source version id
			   my $ne = $s->resultset('BugVer')->new_result({bug => $data->{bug_num},
									 ver_string => $element,
									 found => $ff eq 'found'?1:0,
									}
								       );
			   if (my ($src_pkg,$src_ver) = $element =~ m{^([^\/]+)/(.+)$}) {
			       my $src_pkg_e = $s->resultset('SrcPkg')->single({pkg => $src_pkg});
			       if (defined $src_pkg_e) {
				   $ne->src_pkg($src_pkg_e->id());
				   my $src_ver_e = $s->resultset('SrcVer')->single({src_pkg => $src_pkg_e->id(),
										    ver => $src_ver
										   });
				   $ne->src_ver($src_ver_e->id()) if defined $src_ver_e;
			       }
			   }
			   $ne->insert();
		       }
		   }
	       });
    $s->txn_do(sub {
		   my $t = $s->resultset('BugTag')->search({bug => $data->{bug_num}});
                   $t->delete() if defined $t;
		   $s->populate(BugTag => [[qw(bug tag)], map {[$data->{bug_num}, $_->id()]} values %tags]);
	       });
    # because these bugs reference other bugs which might not exist
    # yet, we can't handle them until we've loaded all bugs. queue
    # them up.
    for my $merge_block (qw(merged block)) {
        my $data_key = $merge_block;
        $data_key .= 'with' if $merge_block eq 'merged';
        if (@{$data->{$data_key}||[]}) {
            my $count = $s->resultset('Bug')->search({id => [@{$data->{$data_key}}]})->count();
            if ($count == @{$data->{$data_key}}) {
                handle_load_bug_queue(db=>$s,
                                      queue => {$merge_block,
                                               {$data->{bug_num},[@{$data->{$data_key}}]}
                                               });
            } else {
                $queue->{$merge_block}{$data->{bug_num}} = [@{$data->{$data_key}}];
            }
        }
    }

    if (not $can_queue and keys %{$queue}) {
        handle_load_bug_queue(db => $s,queue => $queue);
    }

    # still need to handle merges, versions, etc.
}

=item handle_load_bug_queue

     handle_load_bug_queue(db => $schema,queue => $queue);

Handles a queue of operations created by load bug. [These operations
are used to handle cases where a bug referenced by a loaded bug may
not exist yet. In cases where the bugs should exist, the queue is
cleared automatically by load_bug if queue is undefined.

=cut

sub handle_load_bug_queue{
    my %param = validate_with(params => \@_,
                              spec => {db => {type => OBJECT,
                                             },
                                       queue => {type => HASHREF,
                                                },
                                      });
    my $s = $param{db};
    my $queue = $param{queue};
    my %queue_types =
	(merged => {set => 'BugMerged',
		    columns => [qw(bug merged)],
		    bug => 'bug',
		   },
	 blocks => {set => 'BugBlock',
		    columns => [qw(bug blocks)],
		    bug => 'bug',
		   },
	);
    for my $queue_type (keys %queue_types) {
	for my $bug (%{$queue->{$queue_type}}) {
	    my $qt = $queue_types{$queue_type};
	    $s->txn_do(sub {
			   $s->resultset($qt->{set})->search({$qt->{bug},$bug})->delete();
			   $s->populate($qt->{set},[[@{$qt->{columns}}],
                                                    map {[$bug,$_]} @{$queue->{$queue_type}{$bug}}]) if
			       @{$queue->{$queue_type}{$bug}//[]};
		       }
		      );
	}
    }
}

=item load_bug_log -- load bug logs

       load_bug_log(db  => $s,
                    bug => $bug);


=over

=item db -- database 

=item bug -- bug whose log should be loaded

=back

=cut

sub load_bug_log {
    my %param = validate_with(params => \@_,
                              spec => {db => {type => OBJECT,
                                             },
                                       bug => {type => SCALAR,
                                              },
                                       queue => {type => HASHREF,
                                                 optional => 1},
                                      });
    my $s = $param{db};
    my $msg_num=0;
    my %seen_msg_ids;
    my $log = Debbugs::Log->new(bug_num => $param{bug}) or
        die "Unable to open log for $param{bug} for reading: $!";
    while (my $record = $log->read_record()) {
        next unless $record->{type} eq 'incoming-recv';
        my ($msg_id) = $record->{text} =~ /^Message-Id:\s+<(.+)>/im;
        next if defined $msg_id and exists $seen_msg_ids{$msg_id};
        $seen_msg_ids{$msg_id} = 1 if defined $msg_id;
        next if defined $msg_id and $msg_id =~ /handler\..+\.ack(?:info)?\@/;
        my $message = parse($record->{text});
        # search for a message with this message id in the database
        
        # check to see if the subject, to, and from match. if so, it's
        # probably the same message.

        # if not, create a new message

        # add correspondents if necessary

        # link message to bugs if necessary

    }

}

=back

=head2 Debinfo

Commands to handle src and package version loading from debinfo files

=over

=item load_debinfo

     load_debinfo($schema,$binname, $binver, $binarch, $srcname, $srcver);



=cut

sub load_debinfo {
    my ($schema,$binname, $binver, $binarch, $srcname, $srcver) = @_;
    my $sp = $schema->resultset('SrcPkg')->find_or_create({pkg => $srcname});
    my $sv = $schema->resultset('SrcVer')->find_or_create({src_pkg=>$sp->id(),
                                                           ver => $srcver});
    my $arch = $schema->resultset('Arch')->find_or_create({arch => $binarch});
    my $bp = $schema->resultset('BinPkg')->find_or_create({pkg => $binname});
    $schema->resultset('BinVer')->find_or_create({bin_pkg_id => $bp->id(),
                                                  src_ver_id => $sv->id(),
                                                  arch_id    => $arch->id(),
                                                  ver        => $binver,
                                                 });
}


=back

=head Packages

=over

=item load_package

     load_package($schema,$suite,$component,$arch,$pkg)

=cut

sub load_packages {
    my ($schema,$suite,$pkgs,$p) = @_;
    my $suite_id = $schema->resultset('Suite')->
	find_or_create({codename => $suite})->id;
    my %maint_cache;
    my %arch_cache;
    my %source_cache;
    my $src_max_last_modified = $schema->resultset('SrcAssociation')->
	search_rs({suite => $suite_id},
		 {order_by => {-desc => ['me.modified']},
		  rows => 1,
		  page => 1
		 }
		 )->single();
    my $bin_max_last_modified = $schema->resultset('BinAssociation')->
	search_rs({suite => $suite_id},
		 {order_by => {-desc => ['me.modified']},
		  rows => 1,
		  page => 1
		 }
		 )->single();
    print STDERR time." handling packages\n";
    for my $pkg_tuple (@{$pkgs}) {
	my ($arch,$component,$pkg) = @{$pkg_tuple};
	$p->update() if $p;
	if ($arch eq 'source') {
	    my $source = $pkg->{Package};
	    my $source_ver = $pkg->{Version};
	    if (not exists $maint_cache{$pkg->{Maintainer}}) {
		my @addrs = getparsedaddrs($pkg->{Maintainer} // '');
		if (@addrs) {
		    my $mc = $schema->resultset('Correspondent')->
			find_or_create({addr => lc($addrs[0]->address())},
				      {key => 'correspondent_addr_idx'}
				      );
		    my $full_name = $addrs[0]->phrase();
		    $full_name =~ s/^\"|\"$//g;
		    $full_name =~ s/^\s+|\s+$//g;
		    # $sv->discard_changes;
		    my $maint = $schema->resultset('Maintainer')->
			find_or_create({name => $pkg->{Maintainer},
					correspondent => $mc->id},
				      {key => 'maintainer_name_idx'},
				      );
		    $mc->find_or_create_related('correspondent_full_names',
					       {full_name => $full_name},
					       {key => 'correspondent_full_name_correspondent_full_name_idx'}
					       );
		    $mc->update;
		    $maint_cache{$pkg->{Maintainer}} = $maint;
		}
	    }
	    if (not exists $source_cache{$source}{$source_ver}) {
		my $sp = $schema->resultset('SrcPkg')->
		    find_or_create({pkg => $source});
		my $sv = $sp->find_or_create_related('src_vers',
						    {ver => $source_ver});
		$source_cache{$source}{$source_ver} = $sv;
		if (exists $maint_cache{$pkg->{Maintainer}}) {
		    $source_cache{$source}{$source_ver}->
			set_from_related('maintainer',
					 $maint_cache{$pkg->{Maintainer}}
					);
		    $source_cache{$source}{$source_ver}->update;
		}
	    }
	    $schema->resultset('SrcAssociation')->
		update_or_create({suite => $suite_id,
				  source => $source_cache{$source}{$source_ver}->id,
				  modified => 'NOW()',
				 },
				{key => 'src_associations_source_suite'}
				);
	} else {
	    my $ar = $schema->resultset('Arch')->
		find_or_create(arch => $arch);
	    my $bp = $schema->resultset('BinPkg')->
		find_or_create({pkg => $pkg->{Package}});
	    my $source = $pkg->{Source} // $pkg->{Package};
	    my $source_ver = $pkg->{Version};
	    if ($source =~ /^\s*(\S+) \(([^\)]+)\)\s*$/) {
		($source,$source_ver) = ($1,$2);
	    }
	    if (not exists $source_cache{$source}{$source_ver}) {
		my $sp = $schema->resultset('SrcPkg')->
		    find_or_create({pkg => $source});
		my $sv = $sp->find_or_create_related('src_vers',
						    {ver => $source_ver});
		$source_cache{$source}{$source_ver} = $sv;
	    }
	    my $bv = $bp->find_or_create_related('bin_vers',
						{ver => $pkg->{Version},
						 src_ver => $source_cache{$source}{$source_ver}->id,
						 arch => $ar->id,
						});
	    $schema->resultset('BinAssociation')->
		update_or_create({suite => $suite_id,
				  bin => $bv->id,
				  modified => 'NOW()',
				 },
				{key => 'bin_associations_bin_suite'}
				);
	}
    }
    print STDERR time." deleting associations\n";
    # delete old binary associations in this suite which have not recently been
    # modified
    $schema->resultset('BinAssociation')->
	search_rs({suite => $suite_id,
		   modified => {'<',$bin_max_last_modified->modified()},
		  }) if defined
		      $bin_max_last_modified;
    $schema->resultset('SrcAssociation')->
	search_rs({suite => $suite_id,
		   modified => {'<',$src_max_last_modified->modified()},
		  }) if defined
		      $src_max_last_modified;
}

sub load_packages_dbi {
    my ($schema,$suite,$pkgs,$p) = @_;
    my $suite_id = $schema->resultset('Suite')->
	find_or_create({codename => $suite})->id;
    my %maint_cache;
    my %arch_cache;
    my %source_cache;
    my $src_max_last_modified = $schema->resultset('SrcAssociation')->
	search_rs({suite => $suite_id},
		 {order_by => {-desc => ['me.modified']},
		  rows => 1,
		  page => 1
		 }
		 )->single();
    my $bin_max_last_modified = $schema->resultset('BinAssociation')->
	search_rs({suite => $suite_id},
		 {order_by => {-desc => ['me.modified']},
		  rows => 1,
		  page => 1
		 }
		 )->single();
    print STDERR time." handling packages\n";
    # prepare SQL
    my $st = {};
    my $dbi = $schema->storage()->dbh();
    my %s =
        (insert_correspondent => <<'EOF',
WITH ins AS (
INSERT INTO correspondent (addr) VALUES (?)
 ON CONFLICT (addr) DO NOTHING RETURNING id
)
SELECT id FROM ins
UNION ALL
SELECT id FROM correspondent WHERE addr = ?
LIMIT 1;
EOF
         insert_maintainer => <<'EOF',
WITH ins AS (
INSERT INTO maintainer (name,correspondent) VALUES (?,?)
ON CONFLICT (name) DO NOTHING RETURNING id
)
SELECT id FROM ins
UNION ALL
SELECT id FROM maintainer WHERE name = ?
LIMIT 1;
EOF
         insert_correspondent_full_name => <<'EOF',
WITH ins AS (
INSERT INTO correspondent_full_name (correspondent,full_name)
   VALUES (?,?) ON CONFLICT (correspondent,full_name) DO NOTHING RETURNING id
)
SELECT id FROM ins
UNION ALL
SELECT id FROM correspondent_full_name WHERE correspondent=? AND full_name = ?
LIMIT 1;
EOF
         insert_src_pkg => <<'EOF',
WITH ins AS (
INSERT INTO src_pkg (pkg)
   VALUES (?) ON CONFLICT (pkg,disabled) DO NOTHING RETURNING id
)
SELECT id FROM ins
UNION ALL
SELECT id FROM src_pkg where pkg = ? AND disabled = 'infinity'::timestamptz
LIMIT 1;
EOF
         insert_src_ver => <<'EOF',
INSERT INTO src_ver (src_pkg,ver,maintainer)
   VALUES (?,?,?) ON CONFLICT (src_pkg,ver) DO
     UPDATE SET maintainer = ?
   RETURNING id;
EOF
         insert_src_associations => <<'EOF',
INSERT INTO src_associations (suite,source)
   VALUES (?,?) ON CONFLICT (suite,source) DO
     UPDATE SET modified = NOW()
RETURNING id;
EOF
	 insert_bin_pkg => <<'EOF',
WITH ins AS (
INSERT INTO bin_pkg (pkg)
VALUES (?) ON CONFLICT (pkg) DO NOTHING RETURNING id
)
SELECT id FROM ins
UNION ALL
SELECT id FROM bin_pkg where pkg = ?
LIMIT 1;
EOF
	 insert_bin_ver => <<'EOF',
WITH ins AS (
INSERT INTO bin_ver (bin_pkg,src_ver,arch,ver)
VALUES (?,?,?,?) ON CONFLICT (bin_pkg,arch,ver) DO NOTHING RETURNING id
)
SELECT id FROM ins
UNION ALL
SELECT id FROM bin_ver WHERE bin_pkg = ? AND arch = ? AND ver = ?
LIMIT 1;
EOF
	 insert_bin_associations => <<'EOF',
INSERT INTO bin_associations (suite,bin)
   VALUES (?,?) ON CONFLICT (suite,bin) DO
    UPDATE SET modified = NOW()
   RETURNING id;
EOF
	);
    _prepare_sql_statements($dbi,$st,\%s);
    for my $pkg_tuple (@{$pkgs}) {
	my ($arch,$component,$pkg) = @{$pkg_tuple};
	$p->update() if $p;
	sub _get_maintainer {
	    my ($addr,$dbi,$st,$schema) = @_;
	    my $rs =
		$schema->resultset('Maintainer')->
		search({name => $addr},
		      {result_class => 'DBIx::Class::ResultClass::HashRefInflator',
		      }
		      )->first();
	    if (defined $rs) {
		return $rs->{id};
	    }
	    my @addrs = getparsedaddrs($addr // '');
	    my $m_id;
	    my $c_id;
	    if (@addrs) {
		$c_id = _select_one($dbi,$st,
				    'insert_correspondent',
				    lc($addrs[0]->address()),
				    lc($addrs[0]->address()),
				   );
		my $full_name = $addrs[0]->phrase();
		$full_name =~ s/^\"|\"$//g;
		$full_name =~ s/^\s+|\s+$//g;
		_select_one($dbi,$st,
			    'insert_correspondent_full_name',
			    $c_id,
			    $full_name,
			    $c_id,
			    $full_name,
			   );
	    }
	    $m_id =
		_select_one($dbi,$st,
			    'insert_maintainer',
			    $addr,
			    $c_id,
			    $addr,
			   );
	    return $m_id;
	}
	if ($arch eq 'source') {
	    my $source = $pkg->{Package};
	    my $source_ver = $pkg->{Version};
	    if (not exists $maint_cache{$pkg->{Maintainer}}) {
		$maint_cache{$pkg->{Maintainer}} =
		    _get_maintainer($pkg->{Maintainer},$dbi,$st,$schema);
	    }
	    if (not exists $source_cache{$source}{$source_ver}) {
            my $sp_id =
                _select_one($dbi,$st,'insert_src_pkg',
                            $source,
                            $source,
                           );
            my $sv_id =
                _select_one($dbi,$st,'insert_src_ver',
                            $sp_id,
                            $source_ver,
                            $maint_cache{$pkg->{Maintainer}},
                            $maint_cache{$pkg->{Maintainer}});
            $source_cache{$source}{$source_ver} = $sv_id;
        }
	    _select_one($dbi,$st,'insert_src_associations',
			$suite_id,
			$source_cache{$source}{$source_ver}
		       );
	} else {
	    if (not exists $arch_cache{$arch}) {
            my $ar = $schema->resultset('Arch')->
                find_or_create(arch => $arch);
            $arch_cache{$arch} = $ar->id;
	    }
	    my $bp =
            _select_one($dbi,$st,
                        'insert_bin_pkg',
                        $pkg->{Package},
                        $pkg->{Package},
                       );
	    my $source = $pkg->{Source} // $pkg->{Package};
	    my $source_ver = $pkg->{Version};
	    if ($source =~ /^\s*(\S+) \(([^\)]+)\)\s*$/) {
            ($source,$source_ver) = ($1,$2);
	    }
	    if (not exists $source_cache{$source}{$source_ver}) {
            my $sp_id =
                _select_one($dbi,$st,'insert_src_pkg',
                            $source,
                            $source,
                           );
            if (not exists $maint_cache{$pkg->{Maintainer}}) {
                $maint_cache{$pkg->{Maintainer}} =
                    _get_maintainer($pkg->{Maintainer},$dbi,$st,$schema);
            }
            my $sv_id =
                _select_one($dbi,$st,'insert_src_ver',
                            $sp_id,
                            $source_ver,
                            $maint_cache{$pkg->{Maintainer}},
                            $maint_cache{$pkg->{Maintainer}});
            $source_cache{$source}{$source_ver} = $sv_id;
	    }
	    my $bv =
            _select_one($dbi,$st,'insert_bin_ver',
                        $bp,
                        $source_cache{$source}{$source_ver},
                        $arch_cache{$arch},
                        $pkg->{Version},
                        $bp,
                        $arch_cache{$arch},
                        $pkg->{Version},
                       );
        my $ba =
            _select_one($dbi,$st,'insert_bin_associations',
                        $suite_id,
                        $bv,
                       );
	}
    }
    print STDERR time." deleting associations\n";
    # delete old binary associations in this suite which have not recently been
    # modified
    $schema->resultset('BinAssociation')->
        search_rs({suite => $suite_id,
                   modified => {'<',$bin_max_last_modified->modified()},
                  }) if defined
                      $bin_max_last_modified;
    $schema->resultset('SrcAssociation')->
        search_rs({suite => $suite_id,
                   modified => {'<',$src_max_last_modified->modified()},
                  }) if defined
                      $src_max_last_modified;
}

sub _select_one {
    my ($dbh,$sth,$s,@bind_vals) = @_;
    if (not defined $sth->{$s}) {
        die "No such statement '$s'";
    }
    $sth->{$s}->execute(@bind_vals) or
        die "Unable to select one: ".$dbh->errstr();
    my $results = $sth->{$s}->fetchall_arrayref([0]);
    $sth->{$s}->finish();
    return (ref($results) and ref($results->[0]))?$results->[0][0]:undef;
}

sub _prepare_sql_statements {
    my ($dbi,$st,$s) = @_;
    for my $key (keys %{$s}) {
        $st->{$key} = $dbi->prepare($s->{$key}) //
            die "Unable to prepare sql statement: ".$dbi->errstr;
    }
}


=back

=cut

=head Suites

=over

=item load_suite

     load_suite($schema,$codename,$suite,$version,$active);

=cut

sub load_suite {
    my ($schema,$codename,$suite,$version,$active) = @_;
    if (ref($codename)) {
	($codename,$suite,$version) =
	    @{$codename}{qw(Codename Suite Version)};
	$active = 1;
    }
    my $s = $schema->resultset('Suite')->find_or_create({codename => $codename});
    $s->suite_name($suite);
    $s->version($version);
    $s->active($active);
    $s->update();
    return $s;

}

=back

=cut

1;


__END__
