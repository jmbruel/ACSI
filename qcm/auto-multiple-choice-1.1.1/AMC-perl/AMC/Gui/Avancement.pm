#
# Copyright (C) 2008 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Gui::Avancement;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION     = 0.1.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw();
}

sub new {
    my ($entier,%o)=(@_);
    my $self={'entier'=>$entier,
	      'progres'=>0,
	      'debug'=>0,
	      'id'=>'',
	  };
 
    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    bless $self;
    $|++ if($self->{'id'});
    return($self);
}

sub progres {
    my ($self,$suite)=(@_);
    $suite *=  $self->{'entier'};
    $self->{'progres'}+=$suite;
    if($self->{'progres'}>$self->{'entier'}) {
	$suite-=$self->{'progres'}-$self->{'entier'};
	$self->{'progres'}=$self->{'entier'};
    }
    print "===<".$self->{'id'}.">=+$suite\n" if($self->{'id'});
}

sub progres_abs {
    my ($self,$suite)=(@_);
    $self->progres($suite-$self->{'progres'});
}

sub fin {
    my ($self,$suite)=(@_);
    $self->progres_abs(1);
}   

sub etat {
    my ($self)=@_;
    return($self->{'progres'});
}

sub lit {
    my ($self,$s)=(@_);
    my $r='';
    if($s =~ /===<(.*)>=\+([0-9.]+)/) {
	my $id=$1;
	my $suite=$2;
	$self->{'progres'}+=$suite;

	if($self->{'progres'}<0) {
	    print STDERR "progres($self->{'id'})=$self->{'progres'}\n";
	    $self->{'progres'}=0;
	}
	if($self->{'progres'}>1) {
	    print STDERR "progres($self->{'id'})=$self->{'progres'}\n";
	    $self->{'progres'}=1;
	}

	$r=$self->{'progres'};
    }
    return($r);
}

1;
