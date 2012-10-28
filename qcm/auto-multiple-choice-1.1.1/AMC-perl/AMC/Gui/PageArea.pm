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

package AMC::Gui::PageArea;

use Gtk2;
use AMC::Basic;

@ISA=("Gtk2::DrawingArea");

sub add_feuille {
    my ($self,$coul,%oo)=@_;
    bless($self,"AMC::Gui::PageArea");

    $coul='red' if(!$coul);

    $self->{'marks'}='';

    $self->{'i-file'}='';
    $self->{'i-src'}='';
    $self->{'tx'}=1;
    $self->{'ty'}=1;

    $self->{'min_render_size'}=10;

    $self->{'case'}='';
    $self->{'coches'}='';
    $self->{'editable'}=1;

    $self->{'font'}=Pango::FontDescription->from_string("128");

    for (keys %oo) {
	$self->{$_}=$oo{$_} if(defined($self->{$_}));
    }

    $self->{'gc'} = Gtk2::Gdk::GC->new($self->window);

    $self->{'color'}= Gtk2::Gdk::Color->parse($coul);
    $self->window->get_colormap->alloc_color($self->{'color'},TRUE,TRUE);

    if($self->{'marks'}) {
	$self->{'colormark'}= Gtk2::Gdk::Color->parse($self->{'marks'});
	$self->window->get_colormap->alloc_color($self->{'colormark'},TRUE,TRUE);
    }

    return($self);
}

sub set_image {
    my ($self,$image,$layinfo)=@_;
    $self->{'i-file'}=$image;
    if($image =~ /text:(.*)/) {
      my $text=$1;

      my $layout=$self->create_pango_layout($text);
      my $colormap =$self->get_colormap;
      $layout->set_font_description($self->{'font'});
      my ($text_x,$text_y)=$layout->get_pixel_size();
      my $pixmap=Gtk2::Gdk::Pixmap->new(undef,$text_x,$text_y,$colormap->get_visual->depth);
      $pixmap->set_colormap($colormap);
      $pixmap->draw_rectangle($self->style->bg_gc(GTK_STATE_NORMAL),TRUE,0,0,$text_x,$text_y);
      $pixmap->draw_layout($self->style->fg_gc(GTK_STATE_NORMAL),0,0,$layout);
      my $pixbuf=Gtk2::Gdk::Pixbuf->get_from_drawable($pixmap, $colormap,0,0,0,0, $text_x, $text_y);
      $self->{'i-src'}=$pixbuf;
    } elsif($image && -f $image) {
      eval { $self->{'i-src'}=Gtk2::Gdk::Pixbuf->new_from_file($image); };
      if($@) {
	# Error loading scan...
	$self->{'i-src'}='';
      }
    } elsif($image eq 'NONE') {
      $self->{'i-src'}='';
    } else {
	$self->{'i-src'}=Gtk2::Gdk::Pixbuf->new(GDK_COLORSPACE_RGB,0,8,40,10);
	$self->{'i-src'}->fill(0x48B6FF);
    }
    $self->{'layinfo'}=$layinfo;
    $self->{'modifs'}=0;
    $self->window->show;
}

sub get_image {
   my ($self)=@_;
   return($self->{'i-src'});
 }

sub modifs {
    my $self=shift;
    return($self->{'modifs'});
}

sub sync {
    my $self=shift;
    $self->{'modifs'}=0;
}

sub modif {
    my $self=shift;
    $self->{'modifs'}=1;
}

sub choix {
  my ($self,$event)=(@_);

  if(!$self->{'editable'}) {
    return TRUE;
  }

  if($self->{'layinfo'}->{'block_message'}) {
    my $dialog = Gtk2::MessageDialog
      ->new_with_markup(undef,
			'destroy-with-parent',
			'error','ok',
			$self->{'layinfo'}->{'block_message'});
    $dialog->run;
    $dialog->destroy;

    return TRUE;
  }

  if($self->{'layinfo'}->{'box'}) {

      if ($event->button == 1) {
	  my ($x,$y)=$event->coords;
	  debug "Click $x $y\n";
	  for my $i (@{$self->{'layinfo'}->{'box'}}) {

	      if($x<=$i->{'xmax'}*$self->{'rx'} && $x>=$i->{'xmin'}*$self->{'rx'}
		 && $y<=$i->{'ymax'}*$self->{'ry'} && $y>=$i->{'ymin'}*$self->{'ry'}) {
		  $self->{'modifs'}=1;

		  debug " -> box $i\n";
		  $i->{'ticked'}=!$i->{'ticked'};

		  $self->window->show;
	      }
	  }
      }

  }
  return TRUE;
}

sub expose_drawing {
    my ($self,$evenement,@donnees)=@_;
    my $r=$self->allocation();

    return() if(!$self->{'i-src'});

    $self->{'tx'}=$r->width;
    $self->{'ty'}=$r->height;

    debug("Rendering target size: ".$self->{'tx'}."x".$self->{'ty'});

    my $sx=$self->{'tx'}/$self->{'i-src'}->get_width;
    my $sy=$self->{'ty'}/$self->{'i-src'}->get_height;

    if($sx<$sy) {
	$self->{'ty'}=int($self->{'i-src'}->get_height*$sx);
	$sy=$self->{'ty'}/$self->{'i-src'}->get_height;
    }
    if($sx>$sy) {
	$self->{'tx'}=int($self->{'i-src'}->get_width*$sy);
	$sx=$self->{'tx'}/$self->{'i-src'}->get_width;
    }

    return() if($self->{'tx'}<$self->{'min_render_size'}
		|| $self->{'ty'}<$self->{'min_render_size'});

    debug("Rendering with SX=$sx SY=$sy");

    my $i=Gtk2::Gdk::Pixbuf->new(GDK_COLORSPACE_RGB,1,8,$self->{'tx'},$self->{'ty'});

    $self->{'i-src'}->scale($i,0,0,$self->{'tx'},$self->{'ty'},0,0,
			    $sx,$sy,
			    GDK_INTERP_BILINEAR);

    $i->render_to_drawable($self->window,
			   $self->{'gc'},
			   0,0,0,0,
			   $self->{'tx'},
			   $self->{'ty'},
			   'none',0,0);

    debug "Done with rendering";

    if($self->{'layinfo'}->{'box'} || $self->{'layinfo'}->{'namefield'}) {
	my $box;

	debug "Layout drawings...";

	$self->{'rx'}=$self->{'tx'}/$self->{'layinfo'}->{'page'}->{'width'};
	$self->{'ry'}=$self->{'ty'}/$self->{'layinfo'}->{'page'}->{'height'};

	# layout drawings

	if($self->{'marks'}) {
	    $self->{'gc'}->set_foreground($self->{'colormark'});

	    for $box (@{$self->{'layinfo'}->{'namefield'}}) {
		$self->window->draw_rectangle(
		    $self->{'gc'},
		    '',
		    $box->{'xmin'}*$self->{'rx'},
		    $box->{'ymin'}*$self->{'ry'},
		    ($box->{'xmax'}-$box->{'xmin'})*$self->{'rx'},
		    ($box->{'ymax'}-$box->{'ymin'})*$self->{'ry'}
		    );
	    }

	    $box=$self->{'layinfo'}->{'mark'};

	    if($box) {
		for my $i (0..3) {
		    my $j=(($i+1) % 4);
		    $self->window->draw_line($self->{'gc'},
					     $box->[$i]->{'x'}*$self->{'rx'},
					     $box->[$i]->{'y'}*$self->{'ry'},
					     $box->[$j]->{'x'}*$self->{'rx'},
					     $box->[$j]->{'y'}*$self->{'ry'},
			);
		}
	    }

	    for my $box (@{$self->{'layinfo'}->{'digit'}}) {
		$self->window->draw_rectangle(
		    $self->{'gc'},
		    '',
		    $box->{'xmin'}*$self->{'rx'},
		    $box->{'ymin'}*$self->{'ry'},
		    ($box->{'xmax'}-$box->{'xmin'})*$self->{'rx'},
		    ($box->{'ymax'}-$box->{'ymin'})*$self->{'ry'}
		    );

	    }

	}

	## boxes drawings

	$self->{'gc'}->set_foreground($self->{'color'});

	for $box (@{$self->{'layinfo'}->{'box'}}) {
	    $self->window->draw_rectangle(
		$self->{'gc'},
		$box->{'ticked'},
		$box->{'xmin'}*$self->{'rx'},
		$box->{'ymin'}*$self->{'ry'},
		($box->{'xmax'}-$box->{'xmin'})*$self->{'rx'},
		($box->{'ymax'}-$box->{'ymin'})*$self->{'ry'}
		);

	    debug "Done.";
	}
    }
}

1;
