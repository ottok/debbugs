use utf8;
package Debbugs::DB::Result::BugBlock;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Debbugs::DB::Result::BugBlock

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<bug_blocks>

=cut

__PACKAGE__->table("bug_blocks");

=head1 ACCESSORS

=head2 bug_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 blocks

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "bug_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "blocks",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 UNIQUE CONSTRAINTS

=head2 C<bug_blocks_bug_id_blocks_idx>

=over 4

=item * L</bug_id>

=item * L</blocks>

=back

=cut

__PACKAGE__->add_unique_constraint("bug_blocks_bug_id_blocks_idx", ["bug_id", "blocks"]);

=head1 RELATIONS

=head2 block

Type: belongs_to

Related object: L<Debbugs::DB::Result::Bug>

=cut

__PACKAGE__->belongs_to(
  "block",
  "Debbugs::DB::Result::Bug",
  { id => "blocks" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 bug

Type: belongs_to

Related object: L<Debbugs::DB::Result::Bug>

=cut

__PACKAGE__->belongs_to(
  "bug",
  "Debbugs::DB::Result::Bug",
  { id => "bug_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2012-07-17 10:25:29
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:adv4v35ZqedSG4L0CFNPMg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
