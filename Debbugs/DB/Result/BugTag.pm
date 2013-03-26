use utf8;
package Debbugs::DB::Result::BugTag;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Debbugs::DB::Result::BugTag - Bug <-> tag mapping

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

=head1 TABLE: C<bug_tag>

=cut

__PACKAGE__->table("bug_tag");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'bug_tag_id_seq'

=head2 bug

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

Bug id (matches bug)

=head2 tag_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

Tag id (matches tag)

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "bug_tag_id_seq",
  },
  "bug",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "tag_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<bug_tag_bug_tag_id>

=over 4

=item * L</bug>

=item * L</tag_id>

=back

=cut

__PACKAGE__->add_unique_constraint("bug_tag_bug_tag_id", ["bug", "tag_id"]);

=head1 RELATIONS

=head2 bug

Type: belongs_to

Related object: L<Debbugs::DB::Result::Bug>

=cut

__PACKAGE__->belongs_to(
  "bug",
  "Debbugs::DB::Result::Bug",
  { id => "bug" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 tag

Type: belongs_to

Related object: L<Debbugs::DB::Result::Tag>

=cut

__PACKAGE__->belongs_to(
  "tag",
  "Debbugs::DB::Result::Tag",
  { id => "tag_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2013-03-25 18:43:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:fGlaYDuI8YCGvA1gY7DNaQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
