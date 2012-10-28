/*

 Copyright (C) 2008,2010 Alexis Bienvenue <paamc@passoire.fr>

 This file is part of Auto-Multiple-Choice

 Auto-Multiple-Choice is free software: you can redistribute it
 and/or modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation, either version 2 of
 the License, or (at your option) any later version.

 Auto-Multiple-Choice is distributed in the hope that it will be
 useful, but WITHOUT ANY WARRANTY; without even the implied warranty
 of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Auto-Multiple-Choice.  If not, see
 <http://www.gnu.org/licenses/>.

*/

#include<stdlib.h>
#include<stdio.h>
#include<string.h>
#include<ppm.h>

#ifdef NEEDS_GETLINE
  #include<minimal-getline.c>
#endif

#define SEUIL (maxval/2)

/* codes RGB particuliers :

  200,quest,reponse  : case a cocher (avec reponse<200)
  201,nombre,chiffre : case identification ID page
  201,100,i          : marques de position (i=1 a 4)
  201,255,255        : sous la case NOM
  202,0,ID           : composante connexe ID

*/

/*

  coordonnees : (0,0) en haut a gauche

*/

#define MAGICK_MIN 200
#define MAGICK_MAX 202
#define INFO_BLOC 32

#define MAGICK_CC 202

typedef struct {
  double x,y;
} point;

typedef struct {
  double a,b,c;
} ligne;

void calcule_demi_plan(point *a,point *b,ligne *l) {
  double vx,vy;
  vx=b->y - a->y;
  vy=-(b->x - a->x);
  l->a=vx;
  l->b=vy;
  l->c=- a->x*vx - a->y*vy;
}

int evalue_demi_plan(ligne *l,double x,double y) {
  return(l->a*x+l->b*y+l->c <= 0 ? 1 : 0);
}

void erode(pixel **img,int tx,int ty,pixval maxval,double distance) { 
  /* erode le canal G */
  int i,j,dx,dy;
  int d,d2;
  d=(int)distance;
  d2=(int)(distance*distance);
  for(i=0;i<tx;i++) {
    for(j=0;j<ty;j++) {
      PPM_PUTR(img[j][i],PPM_GETG(img[j][i]));
    }}
  for(i=0;i<tx;i++) {
    for(j=0;j<ty;j++) {
      if(PPM_GETG(img[j][i]) > SEUIL) { /* blanc */
	for(dx=-d;dx<=d;dx++) {
	  for(dy=-d;dy<=d;dy++) {
	    if(i+dx>=0 && i+dx<tx &&
	       j+dy>=0 && j+dy<ty &&
	       dx*dx+dy*dy<=d2) {
	      PPM_PUTR(img[j+dy][i+dx],maxval);
	    }
	  }}
      }
    }}
  for(i=0;i<tx;i++) {
    for(j=0;j<ty;j++) {
      PPM_PUTG(img[j][i],PPM_GETR(img[j][i]));
    }}
}

void manhattan(pixel **img,int tx,int ty,pixval maxval,int noir) { 
  /* info en G -> distance en R */
  int i,j,d;
  for(i=0;i<tx;i++) {
    for(j=0;j<ty;j++) {
      if( (PPM_GETG(img[j][i]) > SEUIL ? 1 : 0) ^ noir) {
	PPM_PUTR(img[j][i],0);
      } else {
	d=tx+ty;
	if(i>0) d=PPM_GETR(img[j][i-1])+1;
	if(j>0 && PPM_GETR(img[j-1][i])+1<d) d=PPM_GETR(img[j-1][i])+1;
	PPM_PUTR(img[j][i],d);
      }
    }}
  for(i=tx-1;i>=0;i--) {
    for(j=ty-1;j>=0;j--) {
      d=PPM_GETR(img[j][i]);
      if(i<tx-1 && PPM_GETR(img[j][i+1])+1<d) d=PPM_GETR(img[j][i+1])+1;
      if(j<ty-1 && PPM_GETR(img[j+1][i])+1<d) d=PPM_GETR(img[j+1][i])+1;
      PPM_PUTR(img[j][i],d);
    }}
}

void seuil(pixel **img,int tx,int ty,pixval maxval,
	   int s,int plus_petit_noir) { 
  /* seuil sur R -> RGB */
  int i,j,v;
  for(i=0;i<tx;i++) {
    for(j=0;j<ty;j++) {
      v=( ( PPM_GETR(img[j][i])<=s ? 1 : 0)^plus_petit_noir ? maxval : 0);
      PPM_PUTR(img[j][i],v);
      PPM_PUTG(img[j][i],v);
      PPM_PUTB(img[j][i],v);
    }}
}

void selectionne(pixel **img,int tx,int ty,pixval maxval,
	    int r,int g,int b) { 
  /* que les pixels d'une couleur donnee */
  int i,j,v;
  for(i=0;i<tx;i++) {
    for(j=0;j<ty;j++) {
      v=( PPM_GETR(img[j][i])==r &&
	  PPM_GETG(img[j][i])==g &&
	  PPM_GETB(img[j][i])==b     ? 0 : maxval);
      PPM_PUTR(img[j][i],v);
      PPM_PUTG(img[j][i],v);
      PPM_PUTB(img[j][i],v);
    }}
}

void comp_connexes(pixel **img,int tx,int ty,pixval maxval) { 
  /* info en G -> ID en B, MAGICK en R */
  int x,y,x1,y1,imax,i,n,ancien;
  int *imaxlig;
  imax=0;
  n=0;
  imaxlig=malloc(tx*sizeof(int));

  for(x=0;x<tx;x++) {
    for(y=0;y<ty;y++) {
      if(x>0 && PPM_GETB(img[y][x-1])>0)
	PPM_PUTB(img[y][x],PPM_GETB(img[y][x-1]));
      else
	PPM_PUTB(img[y][x],0);
    }
    if(x>0) imaxlig[x-1]=imax;
    for(y=0;y<ty;y++) {
      if(PPM_GETG(img[y][x]) <= SEUIL) {
	i=PPM_GETB(img[y][x]);

	if(y>0 && PPM_GETB(img[y-1][x])>0)
	  i=PPM_GETB(img[y-1][x]);

	if(y<ty-1 && PPM_GETB(img[y+1][x])>0) {
	  if(i>0) {
	    ancien=i;
	    i=PPM_GETB(img[y+1][x]);
	    if(i!=ancien) {
	      n--;
	      for(x1=0;x1<=x;x1++) {
		if(x1==x || ancien<=imaxlig[x1]) {
		  for(y1=0;y1<ty;y1++) {
		    if(PPM_GETB(img[y1][x1])==ancien)
		      PPM_PUTB(img[y1][x1],i);
		  }}
	      }
	    }
	  } else {
	    i=PPM_GETB(img[y+1][x]);
	  }
	}
	if(i==0) {
	  i=++imax;
	  n++;
	}
	PPM_PUTB(img[y][x],i);
      } else {
	PPM_PUTB(img[y][x],0);
      }
    }}
  for(x=0;x<tx;x++) {
    for(y=0;y<ty;y++) {
      if(PPM_GETB(img[y][x])>0) {
	PPM_PUTR(img[y][x],MAGICK_CC);
	PPM_PUTG(img[y][x],0);
      } else {
	PPM_PUTR(img[y][x],maxval);
	PPM_PUTB(img[y][x],maxval);
      }
    }}
  free(imaxlig);
  printf("CC %d %d\n",n,imax);
}

void mesure_case(pixel **img,int tx,int ty,pixval maxval,
		 double prop,point *coins) {
  int npix,npixnoir,xmin,xmax,ymin,ymax,x,y;
  ligne lignes[4];
  int i,ok;
  double delta;

  void deplace(int i,int j) {
    coins[i].x+=delta*(coins[j].x-coins[i].x);
    coins[i].y+=delta*(coins[j].y-coins[i].y);
  }

  void restreint(int *x,int *y) {
    if(*x<0) *x=0;
    if(*y<0) *y=0;
    if(*x>=tx) *x=tx-1;
    if(*y>=ty) *y=ty-1;
  }

  npix=0;
  npixnoir=0;
  xmin=tx-1;
  xmax=0;
  ymin=ty-1;
  ymax=0;

  /* reduction de la case */
  delta=(1-prop)/2;
  deplace(0,2);deplace(2,0);
  deplace(1,3);deplace(3,1);

  /* sortie des points utilises pour la mesure */
  for(i=0;i<4;i++) {
    printf("COIN %.3f,%.3f\n",coins[i].x,coins[i].y);
  }

  /* bounding box */
  for(i=0;i<4;i++) {
    if(coins[i].x<xmin) xmin=(int)coins[i].x;
    if(coins[i].x>xmax) xmax=(int)coins[i].x;
    if(coins[i].y<ymin) ymin=(int)coins[i].y;
    if(coins[i].y>ymax) ymax=(int)coins[i].y;
  }

  /* equations des demi-plans */
  calcule_demi_plan(&coins[0],&coins[1],&lignes[0]);
  calcule_demi_plan(&coins[1],&coins[2],&lignes[1]);
  calcule_demi_plan(&coins[2],&coins[3],&lignes[2]);
  calcule_demi_plan(&coins[3],&coins[0],&lignes[3]);
      
  restreint(&xmin,&ymin);
  restreint(&xmax,&ymax);

  for(x=xmin;x<=xmax;x++) {
    for(y=ymin;y<=ymax;y++) {
      ok=1;
      for(i=0;i<4;i++) {
	if(evalue_demi_plan(&lignes[i],(double)x,(double)y)==0) ok=0;
      }
      if(ok==1) {
	npix++;
	if(PPM_GETG(img[y][x]) <= SEUIL) npixnoir++;
      }
    }
  }
      
  printf("PIX %d %d\n",npixnoir,npix);
}

typedef struct {
  int magick,exo,quest;
  int xmin,xmax,ymin,ymax;
} infocol;

void repere_magick(pixel **img,int tx,int ty,pixval maxval) {
  infocol *infos;

  int ninfo,ninfo_alloc;
  int i,x,y,red;
  int en_couleur;

  int trouve_id(int magick,int exo,int quest) {
    int i,ii;
    ii=-1;
    for(i=0;i<ninfo;i++) {
      if(infos[i].magick==magick 
	 && infos[i].exo==exo && infos[i].quest==quest) ii=i;
    }
    if(ii<0) {
      ii=ninfo;

      if(ninfo_alloc<ii+1) {
	ninfo_alloc+=INFO_BLOC;
	infos=(infocol*)realloc(infos,ninfo_alloc*sizeof(infocol));
      }

      infos[ii].magick=magick;
      infos[ii].exo=exo;
      infos[ii].quest=quest;
      infos[ii].xmin=100000;
      infos[ii].ymin=100000;
      infos[ii].xmax=-1;
      infos[ii].ymax=-1;
      ninfo++;
    }
    return(ii);
  }

  void ajoute(int id,int x,int y) {
    if(x > infos[id].xmax) infos[id].xmax=x;
    if(x < infos[id].xmin) infos[id].xmin=x;
    if(y > infos[id].ymax) infos[id].ymax=y;
    if(y < infos[id].ymin) infos[id].ymin=y;
  }


  infos=NULL;
  ninfo_alloc=0;

  ninfo=0;

  for(x=0;x<tx;x++) {
    for(y=0;y<ty;y++) {
      red=PPM_GETR(img[y][x]);
      if(red>=MAGICK_MIN && red<=MAGICK_MAX) {
	en_couleur=0;
	if(red!=PPM_GETG(img[y][x])) en_couleur=1;
	if(red!=PPM_GETB(img[y][x])) en_couleur=1;
	if(en_couleur)
	  ajoute(trouve_id(red,PPM_GETG(img[y][x]),PPM_GETB(img[y][x])),x,y);
      }
    }
  }

  for(i=0;i<ninfo;i++) {
    printf(">> magick=%d exo=%d quest=%d (%d,%d)-(%d,%d) : %d x %d\n",
	   infos[i].magick,infos[i].exo,infos[i].quest,
	   infos[i].xmin,infos[i].ymin,
	   infos[i].xmax,infos[i].ymax,
	   infos[i].xmax-infos[i].xmin,infos[i].ymax-infos[i].ymin
	   );
  }

  free(infos);
}

int main(int argc,char **argv) {
  char *commande;
  char fichier[256];
  size_t taille;

  double prop;
  point coins[4];
  int sel_r,sel_g,sel_b,x,y;

  int tx,ty;
  pixval maxval;
  pixel **img;
  FILE *fo;

  double distance;

  if(argc!=2) {
    printf("! Syntax error: bad arguments number\n__END__\n");
    exit(0);
  }

  fo=fopen(argv[1],"r");

  if(!fo) {
    printf("! Error opening <%s>\n__END__\n",argv[1]);
    exit(0);
  }

  img=ppm_readppm(fo,&tx,&ty,&maxval);
  fclose(fo);

  if(!img) {
    printf("! Error reading <%s>\n__END__\n",argv[1]);
    exit(0);
  }

  printf("__LOAD__ tx=%d ty=%d maxval=%d\n",
	 tx,ty,maxval);

  commande=NULL;
  while(getline(&commande,&taille,stdin)>=6) {
    /* printf("> %s",commande); */

    if(sscanf(commande,"mesure %lf %lf %lf %lf %lf %lf %lf %lf %lf",
	      &prop,
	      &coins[0].x,&coins[0].y,
	      &coins[1].x,&coins[1].y,
	      &coins[2].x,&coins[2].y,
	      &coins[3].x,&coins[3].y)==9
       ) {
      /* "mesure" et 9 arguments : proportion, et 4 points sous la forme x y
	 (dans l' ordre HG HD BD BG) */
      /* retour : nombre de pixels noirs, et total */
      mesure_case(img,tx,ty,maxval,prop,coins);
    } else if(sscanf(commande,"erodes %lf",&distance)==1) {
      erode(img,tx,ty,maxval,distance);
    } else if(sscanf(commande,"erode %lf",&distance)==1) {
      manhattan(img,tx,ty,maxval,0);
      seuil(img,tx,ty,maxval,(int)distance,0);
    } else if(sscanf(commande,"etend %lf",&distance)==1) {
      manhattan(img,tx,ty,maxval,1);
      seuil(img,tx,ty,maxval,(int)distance,1);
    } else if(sscanf(commande,"selectionne %d %d %d",&sel_r,&sel_g,&sel_b)==3) {
      selectionne(img,tx,ty,maxval,sel_r,sel_g,sel_b);
    } else if(sscanf(commande,"sauve %256s",(char*)(&fichier))==1) {
      fo=fopen(fichier,"w");
      ppm_writeppm(fo,img,tx,ty,maxval,0);
      fclose(fo);
    } else if(strcmp(commande,"calccc\n")==0) {
      comp_connexes(img,tx,ty,maxval);
    } else if(strcmp(commande,"magick\n")==0) {
      repere_magick(img,tx,ty,maxval);
    } else if(sscanf(commande,"pixel %d %d",&x,&y)==2) {
      printf(">> RGB=%d %d %d\n",PPM_GETR(img[y][x]),PPM_GETG(img[y][x]),PPM_GETB(img[y][x]));
    } else {
      printf("! Command syntax error.\n");
    }
    printf("__END__\n");
    fflush(stdout);
  }

  free(commande);

  return(0);
}
