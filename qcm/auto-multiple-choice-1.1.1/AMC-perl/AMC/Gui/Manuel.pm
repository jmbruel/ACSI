#! /usr/bin/perl -w
#
# Copyright (C) 2008-2012 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Gui::Manuel;

use Getopt::Long;
use Gtk2 -init;

use XML::Simple;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;

use AMC::Basic;
use AMC::Gui::PageArea;
use AMC::Data;
use AMC::DataModule::capture qw/:zone/;

use constant {
    MDIAG_ID => 0,
    MDIAG_ID_BACK => 1,
    MDIAG_EQM => 2,
    MDIAG_DELTA => 3,
    MDIAG_EQM_BACK => 4,
    MDIAG_DELTA_BACK => 5,
    MDIAG_I => 6,
    MDIAG_STUDENT => 7,
    MDIAG_PAGE => 8,
    MDIAG_COPY => 9,
};

use_gettext;

sub new {
    my %o=(@_);
    my $self={'data-dir'=>'',
	      'sujet'=>'',
	      'etud'=>'',
	      'dpi'=>75,
	      'seuil'=>0.1,
	      'seuil_sens'=>8.0,
	      'seuil_eqm'=>3.0,
	      'fact'=>1/4,
	      'page'=>[],
	      'iid'=>0,
	      'global'=>0,
	      'en_quittant'=>'',
	      'encodage_interne'=>'UTF-8',
	      'image_type'=>'xpm',
	      'editable'=>1,
	      'multiple'=>0,
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    bless $self;

    # recupere la liste des fichiers MEP des pages qui correspondent

    $self->{'data'}=AMC::Data->new($self->{'data-dir'});
    $self->{'layout'}=$self->{'data'}->module('layout');
    $self->{'capture'}=$self->{'data'}->module('capture');

    die "No PDF subject file" if(! $self->{'sujet'});
    die "Subject file ".$self->{'sujet'}." not found" if(! -f $self->{'sujet'});

    my $temp_loc=tmpdir();
    $self->{'temp-dir'} = tempdir( DIR=>$temp_loc,
				   CLEANUP => (!get_debug()) );

    $self->{'tmp-image'}=$self->{'temp-dir'}."/page";

    $self->{'iid'}=0;

    ## GUI

    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{'gui'}=Gtk2::Builder->new();
    $self->{'gui'}->set_translation_domain('auto-multiple-choice');
    $self->{'gui'}->add_from_file($glade_xml);

    for my $k (qw/general area navigation_h navigation_v goto goto_v diag_tree button_photocopy/) {
	$self->{$k}=$self->{'gui'}->get_object($k);
    }

    $self->{'general'}->set_title(__"Page layout")
      if(!$self->{'editable'});

    $self->{'button_photocopy'}->hide() if(!$self->{'multiple'});

    if(!$self->{'editable'}) {
	$self->{'navigation_v'}->show();
    } else {
	$self->{'navigation_h'}->show();
    }

    $self->{'cursor_watch'}=Gtk2::Gdk::Cursor->new('GDK_WATCH');

    AMC::Gui::PageArea::add_feuille
	($self->{'area'},'',
	 'editable'=>$self->{'editable'},
	 'marks'=>($self->{'editable'} ? '' : 'blue'));

    ### modele DIAGNOSTIQUE SAISIE

    if($self->{'editable'}) {

	my ($diag_store,$renderer,$column);

	$diag_store = Gtk2::ListStore->new ('Glib::String',
					    'Glib::String',
					    'Glib::String',
					    'Glib::String',
					    'Glib::String',
					    'Glib::String',
					    'Glib::String',
					    'Glib::String',
					    'Glib::String',
					    'Glib::String',
					    );

	$self->{'diag_tree'}->set_model($diag_store);

	$renderer=Gtk2::CellRendererText->new;
	$column = Gtk2::TreeViewColumn->new_with_attributes (__"page",
							     $renderer,
							     text=> MDIAG_ID,
							     'background'=> MDIAG_ID_BACK);
	$column->set_sort_column_id(MDIAG_ID);
	$self->{'diag_tree'}->append_column ($column);

	$renderer=Gtk2::CellRendererText->new;
	$column = Gtk2::TreeViewColumn->new_with_attributes (__"MSE",
							     $renderer,
							     'text'=> MDIAG_EQM,
							     'background'=> MDIAG_EQM_BACK);
	$column->set_sort_column_id(MDIAG_EQM);
	$self->{'diag_tree'}->append_column ($column);

	$renderer=Gtk2::CellRendererText->new;
	$column = Gtk2::TreeViewColumn->new_with_attributes (__"sensitivity",
							     $renderer,
							     'text'=> MDIAG_DELTA,
							     'background'=> MDIAG_DELTA_BACK);
	$column->set_sort_column_id(MDIAG_DELTA);
	$self->{'diag_tree'}->append_column ($column);

	$self->{'diag_store'}=$diag_store;

	$self->{'general'}->window()->set_cursor($self->{'cursor_watch'});
	Gtk2->main_iteration while ( Gtk2->events_pending );

	$self->maj_list_all;

	$diag_store->set_sort_func(MDIAG_EQM,\&sort_num,MDIAG_EQM);
	$diag_store->set_sort_func(MDIAG_DELTA,\&sort_num,MDIAG_DELTA);
	$diag_store->set_sort_func(MDIAG_ID,\&sort_from_columns,
				   [{'type'=>'n','col'=>MDIAG_STUDENT},
				    {'type'=>'n','col'=>MDIAG_COPY},
				    {'type'=>'n','col'=>MDIAG_PAGE},
				   ]);

	$diag_store->set_sort_column_id(MDIAG_ID,GTK_SORT_ASCENDING);

	$self->{'general'}->window()->set_cursor(undef);
    } else {
	  $self->{'layout'}->begin_read_transaction;
	  $self->{'page'}=$self->{'layout'}->get_pages(0);
	  $self->{'layout'}->end_transaction;
    }

    $self->{'gui'}->connect_signals(undef,$self);

    $self->{'area'}->signal_connect('expose_event'=>\&AMC::Gui::Manuel::expose_area);

    $self->charge_i();

    return($self);
}

###

sub goto_from_list {
    my ($self,$widget, $event) = @_;
    return FALSE unless $event->button == 1;
    return TRUE unless $event->type eq 'button-release';
    my ($path, $column, $cell_x, $cell_y) =
	$self->{'diag_tree'}->get_path_at_pos ($event->x, $event->y);
    if($path) {
	$self->ecrit();
	$self->{'iid'}=$self->{'diag_store'}->get($self->{'diag_store'}->get_iter($path),
						  MDIAG_I);
	$self->charge_i();
    }
    return TRUE;
}

sub maj_list_all {
  my ($self)=@_;
  return if(!$self->{'editable'});

  $self->{'capture'}->begin_read_transaction;
  my $summary=$self->{'capture'}
    ->summaries('darkness_threshold'=>$self->{'seuil'},
		'sensitivity_threshold'=>$self->{'seuil_sens'},
		'mse_threshold'=>$self->{'seuil_eqm'});
  my $capture_free=$self->{'capture'}->no_capture_pages;
  $self->{'capture'}->end_transaction;

  $self->{'page'}=[];
  $self->{'diag_store'}->clear();

  my $i=0;
  for my $p (@$summary) {
    push @{$self->{'page'}},[$p->{'student'},$p->{'page'},$p->{'copy'}];
    $iter=$self->{'diag_store'}->append;
    $self->{'diag_store'}
      ->set($iter,
	    MDIAG_I,$i,
	    MDIAG_ID,pageids_string($p->{'student'},$p->{'page'},$p->{'copy'}),
	    MDIAG_STUDENT,$p->{'student'},
	    MDIAG_PAGE,$p->{'page'},
	    MDIAG_COPY,$p->{'copy'},
	    MDIAG_ID_BACK,$p->{'color'},
	    MDIAG_EQM,$p->{'mse_string'},
	    MDIAG_EQM_BACK,$p->{'mse_color'},
	    MDIAG_DELTA,$p->{'sensitivity_string'},
	    MDIAG_DELTA_BACK,$p->{'sensitivity_color'},
	   );
    $i++;
  }
  for my $p (@$capture_free) {
    push @{$self->{'page'}},[@$p];
    $iter=$self->{'diag_store'}->append;
    $self->{'diag_store'}
      ->set($iter,
	    MDIAG_I,$i,
	    MDIAG_ID,pageids_string(@$p),
	    MDIAG_STUDENT,$p->[0],
	    MDIAG_PAGE,$p->[1],
	    MDIAG_COPY,$p->[2],
	    MDIAG_ID_BACK,undef,
	    MDIAG_EQM,'',
	    MDIAG_EQM_BACK,undef,
	    MDIAG_DELTA,'',
	    MDIAG_DELTA_BACK,undef,
	   );
    $i++;
  }
}

sub maj_list_i {
    my ($self,$i)=(@_);
    return if(!$self->{'editable'});

    my $page=$self->{'page'}->[$i];
    my $iter=model_id_to_iter($self->{'diag_store'},
			      MDIAG_ID,pageids_string(@$page));
    $iter=$self->{'diag_store'}->append if(!$iter);

    $self->{'capture'}->begin_read_transaction;
    my %ps=$self->{'capture'}
      ->page_summary(@$page,
		     'mse_threshold'=>$self->{'seuil_eqm'},
		     'blackness_threshold'=>$self->{'seuil'},
		     'sensitivity_threshold'=>$self->{'seuil_sens'},
		    );
    $self->{'capture'}->end_transaction;

    $self->{'diag_store'}->set($iter,
			       MDIAG_ID,pageids_string(@$page),
			       MDIAG_STUDENT,$page->[0],
			       MDIAG_PAGE,$page->[1],
			       MDIAG_COPY,$page->[2],
			       MDIAG_ID_BACK,$ps{'color'},
			       MDIAG_EQM,$ps{'mse_string'},
			       MDIAG_EQM_BACK,$ps{'mse_color'},
			       MDIAG_DELTA,$ps{'sensitivity'},
			       MDIAG_DELTA_BACK,$ps{'sensitivity_color'},
			       );
    if(defined($i)) {
	$self->{'diag_store'}->set($iter,
				   MDIAG_I,$i);
    }
}

sub choix {
    my ($self,$widget,$event)=(@_);
    $widget->choix($event);
}

sub expose_area {
    my ($widget,$evenement,@donnees)=@_;

    $widget->expose_drawing($evenement,@donnees);
}

sub une_modif {
    my ($self)=@_;
    $self->{'area'}->modif();
}

sub page_id {
    my $i=shift;
    return("+".join('/',map { $i->{$_} } (qw/student page checksum/))."+");
}

sub charge_i {
    my ($self)=(@_);

    $self->{'layinfo'}={};
    if(!$self->{'page'}->[$self->{'iid'}]) {
      $self->{'area'}->set_image('NONE');
      debug_and_stderr "Page $self->{'iid'} not found";
      return();
    }

    my @spc=@{$self->{'page'}->[$self->{'iid'}]};

    debug "ID ".pageids_string(@spc);

    $self->{'layout'}->begin_read_transaction;

    debug "page_info";

    my @ep=@spc[0,1];

    $self->{'info'}=$self->{'layout'}->page_info(@ep);
    my $page=$self->{'info'}->{'subjectpage'};

    debug "PAGE $page";

    ################################
    # fabrication du xpm
    ################################

    debug "Making XPM";

    $self->{'general'}->window()->set_cursor($self->{'cursor_watch'});
    Gtk2->main_iteration while ( Gtk2->events_pending );

    system("pdftoppm","-f",$page,"-l",$page,
	   "-r",$self->{'dpi'},
	   $self->{'sujet'},
	   $self->{'temp-dir'}."/page");
    # recherche de ce qui a ete fabrique...
    opendir(TDIR,$self->{'temp-dir'}) || die "can't opendir $self->{'temp-dir'} : $!";
    my @candidats = grep { /^page-.*\.ppm$/ && -f $self->{'temp-dir'}."/$_" } readdir(TDIR);
    closedir TDIR;
    debug "Candidates : ".join(' ',@candidats);
    my $tmp_ppm=$self->{'temp-dir'}."/".$candidats[0];
    my $tmp_image=$tmp_ppm;

    if($self->{'image_type'} && $self->{'image_type'} ne 'ppm') {
	$tmp_image=$self->{'tmp-image'}.".".$self->{'image_type'};
	debug "ppmto".$self->{'image_type'}." : $tmp_ppm -> $tmp_image";
	system("ppmto".$self->{'image_type'}." \"$tmp_ppm\" > \"$tmp_image\"");
    }

    ################################
    # synchro variables
    ################################

    if($spc[2]==0 && $self->{'multiple'} && $self->{'editable'}) {
      $self->{'layinfo'}->{'block_message'}=sprintf(__"This is a template sheet that you cannot edit. To create a new sheet from this one to be edited, use the '%s' button.",__"Add photocopy");
    } else {

      debug "Getting layout info";

      for (qw/box namefield digit/) { $self->{'layinfo'}->{$_}=[]; }

      my $c;
      my $sth;

      for my $type (qw/box digit namefield/) {
	my $sth=$self->{'layout'}->statement($type.'Info');
	$sth->execute(@ep);
	while($c=$sth->fetchrow_hashref) {
	  push @{$self->{'layinfo'}->{$type}},{%$c};
	}
      }

      $self->{'layinfo'}->{'page'}=$self->{'layout'}->page_info(@ep);

      # mise a jour des cases suivant saisies deja presentes

      for my $i (@{$self->{'layinfo'}->{'box'}}) {
	my $id=$i->{'question'}."."
	  .$i->{'answer'};
	my $t=$self->{'capture'}
	  ->ticked(@spc[0,2],$i->{'question'},$i->{'answer'},
		   $self->{'seuil'});
	$t='' if(!defined($t));
	debug "Q=$id R=$t";
	$i->{'id'}=[@spc];
	$i->{'ticked'}=$t;
      }
    }

    $self->{'layout'}->end_transaction;

    # utilisation

    $self->{'area'}->set_image($tmp_image,
			       $self->{'layinfo'});

    unlink($tmp_ppm);
    unlink($tmp_image) if($tmp_ppm ne $tmp_image && !get_debug());

    # dans la liste

    $self->{'diag_tree'}->set_cursor($self->{'diag_store'}->get_path(model_id_to_iter($self->{'diag_store'},MDIAG_I,$self->{'iid'}))) if($self->{'editable'});

    # fin du traitement...

    $self->{'general'}->window()->set_cursor(undef);
}

sub ecrit {
    my ($self)=(@_);

    return if(!$self->{'editable'});

    my @spc=@{$self->{'page'}->[$self->{'iid'}]};

    if($self->{'area'}->modifs()) {
      debug "Saving ".pageids_string(@spc);

      $self->{'capture'}->begin_transaction;
      $self->{'capture'}->outdate_annotated_page(@spc);

      $self->{'capture'}->set_page_manual(@spc,time());

      for my $i (@{$self->{'layinfo'}->{'box'}}) {
	$self->{'capture'}
	  ->set_manual(@{$i->{'id'}},
		       ZONE_BOX,$i->{'question'},$i->{'answer'},
		       ($i->{'ticked'} ? 1 : 0));
      }

      $self->{'capture'}->end_transaction;

      $self->synchronise();
    }
}

sub synchronise {
    my ($self)=(@_);

    $self->{'area'}->sync();

    $self->maj_list_i($self->{'iid'},undef);
}

sub passe_suivant {
    my ($self)=(@_);

    $self->ecrit();
    $self->{'iid'}++;
    $self->{'iid'}=0 if($self->{'iid'}>$#{$self->{'page'}});
    $self->charge_i();
}

sub passe_precedent {
    my ($self)=(@_);

    $self->ecrit();
    $self->{'iid'}--;
    $self->{'iid'}=$#{$self->{'page'}} if($self->{'iid'}<0);
    $self->charge_i();
}

sub annule {
    my ($self)=(@_);

    $self->charge_i();
}

sub efface_saisie {
    my ($self)=(@_);

    my $p=$self->{'page'}->[$self->{'iid'}];
    $self->{'capture'}->begin_transaction;
    $self->{'capture'}->outdate_annotated_page(@$p);
    $self->{'capture'}->remove_manual(@$p);
    $self->{'capture'}->end_transaction;

    $self->synchronise();
    $self->charge_i();
}

sub duplique_saisie {
   my ($self)=@_;

   my $p=$self->{'page'}->[$self->{'iid'}];
   my ($student,$page,$copy)=@$p;

   $self->{'capture'}->begin_transaction;
   $copy=$self->{'capture'}->new_page_copy($student,$page);
   $self->{'capture'}->variable('annotate_source_change',time());
   $self->{'capture'}->set_page_manual($student,$page,$copy,-1);
   $self->{'capture'}->end_transaction;

   $self->maj_list_all;

   $self->{'iid'}=0;
  CHID: for my $i (0..$#{$self->{'page'}}) {
      my $k=$self->{'page'}->[$i];
      if($k->[0] == $student &&
	 $k->[1] == $page &&
	 $k->[2] == $copy) {
	  $self->{'iid'}=$i;
	  last CHID;
      }
  }

   $self->charge_i;
}

sub ok_quitter {
    my ($self)=(@_);

    $self->ecrit();
    $self->quitter();
}

sub quitter {
    my ($self)=(@_);
    if($self->{'global'}) {
	Gtk2->main_quit;
    } else {
	$self->{'general'}->destroy;
	if($self->{'en_quittant'}) {
	  &{$self->{'en_quittant'}}();
	}
    }
}

sub goto_activate_cb {
    my ($self)=(@_);

    my $dest=$self->{($self->{'editable'} ? 'goto' : 'goto_v')}->get_text();

    $self->ecrit();

    debug "Go to $dest";

    # recherche d'un ID correspondant
    $dest.='/' if($dest !~ m:/:);
    my $did='';
  CHID: for my $i (0..$#{$self->{'page'}}) {
      my $k=pageids_string(@{$self->{'page'}->[$i]});
      if($k =~ /^$dest/) {
	  $self->{'iid'}=$i;
	  last CHID;
      }
  }

    $self->charge_i();
}

1;

__END__

