#
# Copyright (C) 2012 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 2 of
# the License, or (at your option) any later version.
#
# Auto-Multiple-Choice is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Auto-Multiple-Choice.  If not, see
# <http://www.gnu.org/licenses/>.

package AMC::Filter;

sub new {
    my $class = shift;
    my $self={'errors'=>[],
	     'project_options'=>{},
	     };
    bless ($self, $class);
    return $self;
}

sub clear {
  my ($self)=@_;
  $self->{'errors'}=[];
}

sub error {
  my ($self,$error_text)=@_;
  push @{$self->{'errors'}},$error_text;
}

sub errors {
  my ($self)=@_;
  return(@{$self->{'errors'}});
}

sub filter {
  my ($self,$input_file,$output_file)=@_;
}

#####################################################################
# The following methods should NOT be overwritten
#####################################################################

sub set_project_option {
  my ($self,$name,$value)=@_;
  $self->{'project_options'}->{$name}=$value;
  print "VAR: project:$name=$value\n";
}

1;
