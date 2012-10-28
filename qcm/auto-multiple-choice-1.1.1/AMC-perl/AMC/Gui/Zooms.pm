#! /usr/bin/perl
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

package AMC::Gui::Zooms;

use AMC::Basic;
use AMC::DataModule::capture ':zone';

use Gtk2 -init;

use POSIX qw(ceil);

use constant ID_AMC_BOX => 100;

my $col_manuel = Gtk2::Gdk::Color->new(223*256,224*256,133*256);
my $col_modif = Gtk2::Gdk::Color->new(226*256,184*256,178*256);

sub new {
    my %o=(@_);

    my $self={
	'n_cols'=>4,
	'factor'=>0.75,
	'seuil'=>0.15,
	'prop_min'=>0.30,
	'prop_max'=>0.60,
	'global'=>0,
	'zooms_dir'=>"",
	'page_id'=>[],
	'data'=>'',
	'data-dir'=>'',
	'size-prefs'=>'',
	'encodage_interne'=>'UTF-8',
    };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    $self->{'ids'}=[];
    $self->{'pb_src'}={};
    $self->{'real_src'}={};
    $self->{'pb'}={};
    $self->{'image'}={};
    $self->{'label'}={};
    $self->{'n_ligs'}={};
    $self->{'position'}={};
    $self->{'eb'}={};
    $self->{'conforme'}=1;

    bless $self;

    if($self->{'data'}) {
	$self->{'_capture'}=$self->{'data'};
    } else {
	debug "Connecting to database...";
	$self->{'_capture'}=AMC::Data->new($self->{'data-dir'})
	  ->module('capture');
	debug "ok";
    }

    if($self->{'size-prefs'}) {
	$self->{'factor'}=$self->{'size-prefs'}->{'zoom_window_factor'}
	if($self->{'size-prefs'}->{'zoom_window_factor'});
    }
    $self->{'factor'}=0.1 if($self->{'factor'}<0.1);
    $self->{'factor'}=5 if($self->{'factor'}>5);

    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{'gui'}=Gtk2::Builder->new();
    $self->{'gui'}->set_translation_domain('auto-multiple-choice');
    $self->{'gui'}->add_from_file($glade_xml);

    for(qw/main_window zooms_table_0 zooms_table_1 decoupage view_0 view_1 scrolled_0 scrolled_1 label_0 label_1 event_0 event_1 button_apply button_close info/) {
	$self->{$_}=$self->{'gui'}->get_object($_);
    }

    $self->{'label_0'}->set_markup('<b>'.$self->{'label_0'}->get_text.'</b>');
    $self->{'label_1'}->set_markup('<b>'.$self->{'label_1'}->get_text.'</b>');
    $self->{'info'}->set_markup('<b>'.sprintf(__("Boxes zooms for page %s"),
					      pageids_string(@{$self->{'page_id'}})).'</b>');

    $self->{'decoupage'}->child1_resize(1);
    $self->{'decoupage'}->child2_resize(1);

    for(0,1) {
	$self->{'event_'.$_}->drag_dest_set('all', [GDK_ACTION_MOVE],
					    {'target' => 'STRING',
					      'flags' => [],
					      'info' => ID_AMC_BOX },
					    );
	$self->{'event_'.$_}->signal_connect(
	    'drag-data-received' => \&target_drag_data_received,[$self,$_]);
    }

    $self->{'gui'}->connect_signals(undef,$self);

    if($self->{'size-prefs'}) {
	my @s=$self->{'main_window'}->get_size();
	$s[1]=$self->{'size-prefs'}->{'zoom_window_height'};
	$s[1]=200 if($s[1]<200);
	$self->{'main_window'}->resize(@s);
    }

    $self->load_boxes();

    return($self);
}

sub clear_boxes {
    my ($self)=@_;

    for(0,1) { $self->vide($_); }
    $self->{'ids'}=[];
    $self->{'pb_src'}={};
    $self->{'real_src'}={};
    $self->{'pb'}={};
    $self->{'image'}={};
    $self->{'label'}={};
    $self->{'n_ligs'}={};
    $self->{'position'}={};
    $self->{'eb'}={};
    $self->{'eff_pos'}={};
    $self->{'auto_pos'}={};
    $self->{'conforme'}=1;
    $self->{'button_apply'}->hide();
}

sub scrolled_update {
  my ($self)=@_;
  for my $cat (0,1) {
    $self->{'scrolled_'.$cat}->set_policy('never','automatic');
  }
}

sub load_positions {
  my ($self)=@_;
  $self->{'_capture'}->begin_read_transaction;

  my $page=$self->{'_capture'}->get_page(@{$self->{'page_id'}});

  my $sth=$self->{'_capture'}->statement('pageZonesD');
  $sth->execute(@{$self->{'page_id'}},ZONE_BOX);
  while (my $z = $sth->fetchrow_hashref) {
    my $id=$z->{'id_a'}.'-'.$z->{'id_b'};
    my $auto_pos=($z->{'black'} > $z->{'total'}*$self->{'seuil'} ? 1 : 0);
    my $eff_pos=($page->{'timestamp_manual'} && $z->{'manual'}>=0 ? $z->{'manual'} :
		 $auto_pos);
    $self->{'eff_pos'}->{$id}=$eff_pos;
    $self->{'auto_pos'}->{$id}=$auto_pos;
  }

  $self->{'_capture'}->end_transaction;
}

sub safe_pixbuf {
  my ($self,$file)=@_;
  my $p='';
  if(-f $file) {
    # Try to load PNG file. This can fail in case of problem (for
    # example if mimetype was not detected correctly due to special
    # file content matching other mime types).
    eval { $p=Gtk2::Gdk::Pixbuf->new_from_file($file); };
    return($p,1) if($p);
    # Try using Graphics::Magick to convert PNG->XPM
    my $i=magick_perl_module()->new;
    $i->Read($file);
    my @b=$i->ImageToBlob("magick"=>'xpm');
    if($b[0]) {
      $b[0] =~ s:/\*.*\*/::g;
      $b[0] =~ s:static char.*::;
      $b[0] =~ s:};::;
      my @xpm=grep { $_ ne '' }
	map { s/^\"//;s/\",?$//;$_; }
	  split(/\n+/,$b[0]);
      eval { $p=Gtk2::Gdk::Pixbuf->new_from_xpm_data(@xpm); };
      return($p,1) if($p);
    }
  }
  # No success at all: replace the zoom image by a question mark
  my $g=$self->{'main_window'};
  my $layout=$g->create_pango_layout("?");
  my $colormap =$g->get_colormap;
  $layout->set_font_description(Pango::FontDescription->from_string("128"));
  my ($text_x,$text_y)=$layout->get_pixel_size();
  my $pixmap=Gtk2::Gdk::Pixmap->new(undef,$text_x,$text_y,$colormap->get_visual->depth);
  $pixmap->set_colormap($colormap);
  $pixmap->draw_rectangle($g->style->bg_gc(GTK_STATE_NORMAL),TRUE,0,0,$text_x,$text_y);
  $pixmap->draw_layout($g->style->fg_gc(GTK_STATE_NORMAL),0,0,$layout);
  $p=Gtk2::Gdk::Pixbuf->get_from_drawable($pixmap, $colormap,0,0,0,0, $text_x, $text_y);
  return($p,0);
}

sub load_boxes {
    my ($self)=@_;

    my @ids;

    $self->load_positions;

    $self->{'_capture'}->begin_read_transaction;

    my $sth=$self->{'_capture'}->statement('pageZonesD');
    $sth->execute(@{$self->{'page_id'}},ZONE_BOX);
    while (my $z = $sth->fetchrow_hashref) {

      my $id=$z->{'id_a'}.'-'.$z->{'id_b'};
      my $fid=$self->{'zooms_dir'}."/".$z->{'image'};

      if(-f $fid) {

	($self->{'pb_src'}->{$id},$self->{'real_src'}->{$id})
	  =$self->safe_pixbuf($fid);

	$self->{'image'}->{$id}=Gtk2::Image->new();

	$self->{'label'}->{$id}=
	  Gtk2::Label->new(sprintf("%.3f",
				   $self->{'_capture'}
				   ->zone_darkness($z->{'zoneid'})));
	$self->{'label'}->{$id}->set_justify(GTK_JUSTIFY_LEFT);

	my $hb=Gtk2::HBox->new();
	$self->{'eb'}->{$id}=Gtk2::EventBox->new();
	$self->{'eb'}->{$id}->add($hb);

	$hb->add($self->{'image'}->{$id});
	$hb->add($self->{'label'}->{$id});

	$self->{'eb'}->{$id}->drag_source_set(GDK_BUTTON1_MASK,
					      GDK_ACTION_MOVE,
					      {
					       target => 'STRING',
					       flags => [],
					       info => ID_AMC_BOX,
					      });
	$self->{'eb'}->{$id}
	  ->signal_connect('drag-data-get' => \&source_drag_data_get,
			   $id );
	$self->{'eb'}->{$id}
	  ->signal_connect('drag-begin'=>sub {
			     $self->{'eb'}->{$id}
			       ->drag_source_set_icon_pixbuf($self->{'image'}->{$id}->get_pixbuf);
			   });

	$self->{'position'}->{$id}=$self->{'eff_pos'}->{$id};

	push @ids,$id;
      } else {
	debug_and_stderr "Zoom file not found: $fid";
      }
    }

    $self->{'_capture'}->end_transaction;

    $self->{'ids'}=[@ids];

    $self->{'conforme'}=1;

    $self->remplit(0);
    $self->remplit(1);
    $self->zoom_it();

    $self->{'main_window'}->show_all();
    $self->{'button_apply'}->hide();

    Gtk2->main_iteration while ( Gtk2->events_pending );

    $self->ajuste_sep();

    $self->scrolled_update;

    my $va=$self->{'view_0'}->get_vadjustment();
    $va->value($va->upper()-$va->page_size);
    $va->changed;

    if($self->{'conforme'}) {
	$self->{'button_apply'}->hide();
    } else {
	$self->{'button_apply'}->show();
    }

}

sub refill {
    my ($self)=@_;
    $self->{'conforme'}=1;
    for(0,1) { $self->vide($_); }
    for(0,1) { $self->remplit($_); }
    if($self->{'conforme'}) {
	$self->{'button_apply'}->hide();
    } else {
	$self->{'button_apply'}->show();
    }
    $self->scrolled_update;
}

sub page {
    my ($self,$id,$zd,$forget_it)=@_;
    if(!$self->{'conforme'}) {
	return() if($forget_it);

	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($self->{'main_window'},
			      'destroy-with-parent',
			      'warning','yes-no',
			      __("You moved some boxes to correct automatic data query, but this work is not saved yet.")." ".__("Dou you want to save these modifications before looking at another page?")
	    );
	my $reponse=$dialog->run;
	$dialog->destroy;
	if($reponse eq 'yes') {
	    $self->apply;
	}
    }
    $self->clear_boxes;
    $self->{'page_id'}=$id;
    $self->{'zooms_dir'}=$zd;
    $self->{'info'}->set_markup('<b>'.sprintf(__("Boxes zooms for page %s"),
					      pageids_string(@{$self->{'page_id'}})).'</b>');
    $self->load_boxes;
}

sub source_drag_data_get {
    my ($widget, $context, $data, $info, $time,$string) = @_;
    $data->set_text($string,-1);
}

sub target_drag_data_received {
    my ($widget, $context, $x, $y, $data, $info, $time,$args) = @_;
    my ($self,$cat)=@$args;
    my $id=$data->get_text();
    debug "Page ".pageids_string(@{$self->{'page_id'}})
      .": move $id to category $cat\n";
    if($self->{'position'}->{$id} != $cat) {
	$self->{'position'}->{$id}=$cat;
	$self->refill;
    }
}

sub vide {
    my ($self,$cat)=@_;
    for($self->{'zooms_table_'.$cat}->get_children) {
	$self->{'zooms_table_'.$cat}->remove($_);
    }
}

sub remplit {
    my ($self,$cat)=@_;

    my @good_ids=grep { $self->{'position'}->{$_} == $cat } (@{$self->{'ids'}});

    my $n_ligs=ceil((@good_ids ? (1+$#good_ids)/$self->{'n_cols'} : 1));
    $self->{'zooms_table_'.$cat}->resize($n_ligs,$self->{'n_cols'});
    $self->{'n_ligs'}->{$cat}=$n_ligs;

    for my $i (0..$#good_ids) {
	my $id=$good_ids[$i];
	my $x=$i % $self->{'n_cols'};
	my $y=int($i/$self->{'n_cols'});

	if($self->{'eff_pos'}->{$id} != $cat) {
	    $self->{'eb'}->{$id}->modify_bg(GTK_STATE_NORMAL,$col_modif);
	    $self->{'conforme'}=0;
	} else {
	    if($self->{'auto_pos'}->{$id} == $cat) {
		$self->{'eb'}->{$id}->modify_bg(GTK_STATE_NORMAL,undef);
	    } else {
		$self->{'eb'}->{$id}->modify_bg(GTK_STATE_NORMAL,$col_manuel);
	    }
	}

	$self->{'zooms_table_'.$cat}->attach($self->{'eb'}->{$id},
					     $x,$x+1,$y,$y+1,[],[],4,3);
    }
}

sub ajuste_sep {
    my ($self)=@_;
    my $s=$self->{'decoupage'}->get_property('max-position');
    my $prop=$self->{'n_ligs'}->{0}/($self->{'n_ligs'}->{0}+$self->{'n_ligs'}->{1});
    $prop=$self->{'prop_min'} if($prop<$self->{'prop_min'});
    $prop=$self->{'prop_max'} if($prop>$self->{'prop_max'});
    $self->{'decoupage'}->set_position($prop*$s);
}

sub zoom_it {
    my ($self)=@_;
    my $x=0;
    my $y=0;
    my $n=0;

    # show all boxes with scale factor $self->{'factor'}

    for my $id (grep { $self->{'real_src'}->{$_} }
      (@{$self->{'ids'}})) {
      my $tx=int($self->{'pb_src'}->{$id}->get_width * $self->{'factor'});
      my $ty=int($self->{'pb_src'}->{$id}->get_height * $self->{'factor'});
      $x+=$tx;$y+=$ty;$n++;
      $self->{'pb'}->{$id}=$self->{'pb_src'}->{$id}
	->scale_simple($tx,$ty,GDK_INTERP_BILINEAR);
      $self->{'image'}->{$id}->set_from_pixbuf($self->{'pb'}->{$id});
    }

    # compute average size of the images

    if($n>0) {
      $x=int($x/$n);$y=int($y/$n);
    } else {
      $x=32;$y=32;
    }

    # show false zooms (question mark replacing the zooms when the
    # zoom file couldn't be loaded) at this average size

    for my $id (grep { ! $self->{'real_src'}->{$_} }
      (@{$self->{'ids'}})) {
      my $fx=$x/$self->{'pb_src'}->{$id}->get_width;
      my $fy=$y/$self->{'pb_src'}->{$id}->get_height;
      $fx=$fy if($fy<$fx);
      my $tx=int($self->{'pb_src'}->{$id}->get_width * $fx);
      my $ty=int($self->{'pb_src'}->{$id}->get_height * $fx);
      $self->{'pb'}->{$id}=$self->{'pb_src'}->{$id}
	->scale_simple($tx,$ty,GDK_INTERP_BILINEAR);
      $self->{'image'}->{$id}->set_from_pixbuf($self->{'pb'}->{$id});
    }

    # resize window

    $self->{'event_0'}->queue_resize();
    $self->{'event_1'}->queue_resize();

    my @size=$self->{'main_window'}->get_size();
    $size[0]=1;
    $self->{'main_window'}->resize(@size);
}

sub zoom_avant {
    my ($self)=@_;
    $self->{'factor'} *= 1.25;
    $self->zoom_it();
}

sub zoom_arriere {
    my ($self)=@_;
    $self->{'factor'} /= 1.25;
    $self->zoom_it();
}

sub quit {
    my ($self)=@_;

    if($self->{'size-prefs'}) {
	my ($x,$y)=$self->{'main_window'}->get_size();
	$self->{'size-prefs'}->{'zoom_window_factor'}=$self->{'factor'};
	$self->{'size-prefs'}->{'zoom_window_height'}=$y;
	$self->{'size-prefs'}->{'_modifie_ok'}=1;
    }

    if(!$self->{'conforme'}) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($self->{'main_window'},
			      'destroy-with-parent',
			      'warning','yes-no',
			      __("You moved some boxes to correct automatic data query, but this work is not saved yet.")." ".__("Dou you really want to close and ignore these modifications?")
	    );
	my $reponse=$dialog->run;
	$dialog->destroy;
	return() if($reponse eq 'no');
    }

    if($self->{'global'}) {
        Gtk2->main_quit;
    } else {
        $self->{'main_window'}->destroy;
    }
}

sub actif {
    my ($self)=@_;
    return($self->{'main_window'} &&
	   $self->{'main_window'}->realized);
}

sub checked {
    my ($self,$id)=@_;
    if(defined($self->{'position'}->{$id})) {
	return($self->{'position'}->{$id});
    } else {
	$self->{'eff_pos'}->{$id};
    }
}

sub apply {
    my ($self)=@_;

    # save modifications to manual analysis data

    $self->{'_capture'}->begin_transaction;
    $self->{'_capture'}->outdate_annotated_page(@{$self->{'page_id'}});

    debug "Saving manual data for ".pageids_string(@{$self->{'page_id'}});

    $self->{'_capture'}
      ->statement('setManualPage')
	->execute(time(),
		  @{$self->{'page_id'}});

    my $sth=$self->{'_capture'}->statement('pageZonesD');
    $sth->execute(@{$self->{'page_id'}},ZONE_BOX);
    while (my $z = $sth->fetchrow_hashref) {

      my $id=$z->{'id_a'}.'-'.$z->{'id_b'};

      $self->{'_capture'}
	->statement('setManual')
	  ->execute($self->checked($id),
		    @{$self->{'page_id'}},
		    ZONE_BOX,$z->{'id_a'},$z->{'id_b'});
    }

    $self->{'_capture'}->end_transaction;

    $self->load_positions;
    $self->refill;
}

1;
