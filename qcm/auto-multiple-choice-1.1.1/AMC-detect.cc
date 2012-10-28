/*

 Copyright (C) 2011-2012 Alexis Bienvenue <paamc@passoire.fr>

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

#include <math.h>
#include <cstddef>
#include "cv.h"
#include "highgui.h"
#include <stdio.h>
#include <locale.h>

#include <errno.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

#ifdef NEEDS_GETLINE
  #include<minimal-getline.c>
#endif

#if CV_MAJOR_VERSION > 2
  #define OPENCV_21 1
  #define OPENCV_20 1
#else
  #if CV_MAJOR_VERSION == 2
    #define OPENCV_20 1
    #if CV_MINOR_VERSION >= 1
       #define OPENCV_21 1
    #endif
    #if CV_MINOR_VERSION >= 3
       #define OPENCV_23 1
    #endif
  #endif
#endif

#define GET_PIXEL(src,x,y) *((uchar*)(src->imageData+src->widthStep*(y)+src->nChannels*(x)))
#define PIXEL(src,x,y) GET_PIXEL(src,x,y)>100

#define BLEU CV_RGB(38,69,223)
#define ROSE CV_RGB(223,38,203)

#define SWAP(x,y,tmp) tmp=x;x=y;y=tmp
#define SGN_ROT (1-2*upside_down)

void agrege_init(double tx,double ty,double* coins_x,double* coins_y) {
  coins_x[0]=tx;coins_y[0]=ty;
  coins_x[1]=0;coins_y[1]=ty;
  coins_x[2]=0;coins_y[2]=0;
  coins_x[3]=tx;coins_y[3]=0;
}

#define AGREGE_POINT(op,comp,i) if((x op y) comp (coins_x[i] op coins_y[i])) { coins_x[i]=x;coins_y[i]=y; }

void agrege(double x,double y,double* coins_x,double* coins_y) {
  AGREGE_POINT(+,<,0)
  AGREGE_POINT(+,>,2)
  AGREGE_POINT(-,>,1)
  AGREGE_POINT(-,<,3)
}

void load_image(IplImage** src,char *filename,
		int ignore_red,double threshold=0.6,int view=0) {
  IplImage* color;
  double max;

  if(ignore_red) {
    if((color=cvLoadImage(filename,
#ifdef OPENCV_23
			  CV_LOAD_IMAGE_ANYCOLOR
#else
			  CV_LOAD_IMAGE_UNCHANGED
#endif
			  ))!= NULL) {
      printf("loaded\n");
      if(color->nChannels>=3) {
	/* keeps only red channel */
	cvSetImageCOI(color,3);
	*src=cvCreateImage( cvGetSize(color), color->depth, 1 );
	cvCopy(color,*src);
	cvReleaseImage(&color);
      } else if(color->nChannels!=1) {
	printf("! LOAD : Scan file with 2 channels [%s]\n",filename);
	return;
      } else {
	*src=color;
      }
    } else {
      printf("! LOAD : Error loading scan file in ANYCOLOR [%s]\n",filename);
      return;
    }
  } else {
    if((*src=cvLoadImage(filename, CV_LOAD_IMAGE_GRAYSCALE))==NULL) {
      printf("! LOAD : Error loading scan file in GRAYSCALE [%s]\n",filename);
      return;
    }
  }

  cvMinMaxLoc(*src,NULL,&max);
  cvSmooth(*src,*src,CV_GAUSSIAN,3,3,1);
  cvThreshold(*src,*src, max*threshold, 255, CV_THRESH_BINARY_INV );
  
  if((*src)->origin==1) {
    printf(": Image flip\n");
    cvFlip(*src,NULL,0);
  }
}

void pre_traitement(IplImage* src,int lissage_trous,int lissage_poussieres) {
  IplConvKernel* trous=cvCreateStructuringElementEx(1+2*lissage_trous,1+2*lissage_trous,
						    lissage_trous,lissage_trous,CV_SHAPE_ELLIPSE);
  IplConvKernel* poussieres=cvCreateStructuringElementEx(1+2*lissage_poussieres,1+2*lissage_poussieres,
							 lissage_poussieres,lissage_poussieres,CV_SHAPE_ELLIPSE);

  printf("Morph: +%d -%d\n",lissage_trous,lissage_poussieres);
  cvMorphologyEx(src,src,NULL,trous,CV_MOP_CLOSE);
  cvMorphologyEx(src,src,NULL,poussieres,CV_MOP_OPEN);

  cvReleaseStructuringElement(&trous);
  cvReleaseStructuringElement(&poussieres);
}

typedef struct {
  double a,b,c,d,e,f;
} linear_transform;

void transforme(linear_transform* t,double x,double y,double* xp,double* yp) {
  *xp=t->a*x+t->b*y+t->e;
  *yp=t->c*x+t->d*y+t->f;
}

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

double moyenne(double *x, int n) {
  double s=0;
  for(int i=0;i<n;i++) s+=x[i];
  return(s/n);
}

double scalar_product(double *x,double *y,int n) {
  double sx,sy,sxy;
  sx=0;sy=0;sxy=0;
  for(int i=0;i<n;i++) {
    sx+=x[i];sy+=y[i];sxy+=x[i]*y[i];
  }
  return(sxy/n-sx/n*sy/n);
}

void sys_22(double a,double b,double c,double d,double e,double f,
	      double *x,double *y) {
  double delta=a*d-b*c;
  if(delta==0) {
    printf("! NONINV : Non-invertible system.\n");
    return;
  }
  *x=(d*e-b*f)/delta;
  *y=(a*f-c*e)/delta;
}

double sqr(double x) { return(x*x); }

double optim(double* points_x,double* points_y,
	     double* points_xp,double* points_yp,
	     int n,
	     linear_transform* t) {
  double sxx=scalar_product(points_x,points_x,n);
  double sxy=scalar_product(points_x,points_y,n);
  double syy=scalar_product(points_y,points_y,n);
  
  double sxxp=scalar_product(points_x,points_xp,n);
  double syxp=scalar_product(points_y,points_xp,n);
  double sxyp=scalar_product(points_x,points_yp,n);
  double syyp=scalar_product(points_y,points_yp,n);

  sys_22(sxx,sxy,sxy,syy,sxxp,syxp,&(t->a),&(t->b));
  sys_22(sxx,sxy,sxy,syy,sxyp,syyp,&(t->c),&(t->d));
  t->e=moyenne(points_xp,n)-(t->a*moyenne(points_x,n)+t->b*moyenne(points_y,n));
  t->f=moyenne(points_yp,n)-(t->c*moyenne(points_x,n)+t->d*moyenne(points_y,n));

  double mse=0;
  for(int i=0;i<n;i++) {
    mse+=sqr(points_xp[i]-(t->a*points_x[i]+t->b*points_y[i]+t->e));
    mse+=sqr(points_yp[i]-(t->c*points_x[i]+t->d*points_y[i]+t->f));
  }
  mse=sqrt(mse/n);
  return(mse);
}

void calage(IplImage* src,IplImage* illustr,
	    double taille_orig_x,double taille_orig_y,
	    double dia_orig,
	    double tol_plus,double tol_moins,
	    double* coins_x,double *coins_y,
	    IplImage** dst,int view=0) {
  CvPoint coins_int[4];
  int n_cc;

  /* target min and max size */
  
  double rx=src->width/taille_orig_x;
  double ry=src->height/taille_orig_y;
  double target=dia_orig*(rx+ry)/2;
  double target_max=target*(1+tol_plus);
  double target_min=target*(1-tol_moins);

  pre_traitement(src,
		 1+(int)((target_min+target_max)/2 /20),
		 1+(int)((target_min+target_max)/2 /8));

  if(view==2) {
    *dst=cvCreateImage( cvGetSize(src), IPL_DEPTH_8U, 3 );
    cvConvertImage(src,*dst);
    cvNot(*dst,*dst);
  }

  printf("Target size: %.1f ; %.1f\n",target_min,target_max);

  static CvMemStorage* storage = cvCreateMemStorage(0);
  CvSeq* contour = 0;
	  
  cvFindContours( src, storage, &contour, sizeof(CvContour),
		  CV_RETR_CCOMP, CV_CHAIN_APPROX_SIMPLE );

#ifdef OPENCV_21
  if(view==1) {
    *dst=cvCreateImage( cvGetSize(src), 8, 3 );
    cvZero( *dst );
  }
#endif

  agrege_init(src->width,src->height,coins_x,coins_y);
  n_cc=0;

  printf("Detected connected components:\n");

  for( ; contour != 0; contour = contour->h_next ) {
    CvRect rect=cvBoundingRect(contour);
    if(rect.width<=target_max && rect.width>=target_min &&
       rect.height<=target_max && rect.height>=target_min) {
      agrege(rect.x+rect.width/2.0,rect.y+rect.height/2.0,coins_x,coins_y);
      
      printf("(%d;%d)+(%d;%d)\n",
	     rect.x,rect.y,rect.width,rect.height);
      n_cc++;
	
#ifdef OPENCV_21
     if(view==1) {
	CvScalar color = CV_RGB( rand()&255, rand()&255, rand()&255 );
	cvRectangle(*dst,cvPoint(rect.x,rect.y),cvPoint(rect.x+rect.width,rect.y+rect.height),color);
	cvDrawContours( *dst, contour, color, color, -1, CV_FILLED, 8 );
      }
#endif
     if(view==2) {
       CvScalar color = CV_RGB( 60,198,127 );
	cvRectangle(*dst,cvPoint(rect.x,rect.y),cvPoint(rect.x+rect.width,rect.y+rect.height),color);
	cvDrawContours( *dst, contour, color, color, -1, CV_FILLED, 8 );
     }
    }
  }

  if(n_cc>=4) {
    for(int i=0;i<4;i++) {
      if(view>0 || illustr!=NULL) {
	coins_int[i].x=(int)coins_x[i];
	coins_int[i].y=(int)coins_y[i];
      }
      printf("Frame[%d]: %.1f ; %.1f\n",i,coins_x[i],coins_y[i]);
    }
    
    if(view==1) {
#ifdef OPENCV_21
      for(int i=0;i<4;i++) {
	cvLine(*dst,coins_int[i],coins_int[(i+1)%4],CV_RGB(255,255,255),1,CV_AA);
      }
#endif
    }
    if(view==2) {
      for(int i=0;i<4;i++) {
	cvLine(*dst,coins_int[i],coins_int[(i+1)%4],CV_RGB(193,29,27),1,CV_AA);
      }
    }

    if(illustr!=NULL) {
      for(int i=0;i<4;i++) {
	cvLine(illustr,coins_int[i],coins_int[(i+1)%4],BLEU,1,CV_AA);
      }
    }
  } else {
    printf("! NMARKS=%d : Not enought marks detected.\n",n_cc);
  }

  cvClearMemStorage(storage);
}

#define CLOSER(pointa,pointb,cn,dist,delta) dist=delta*(pointb.cn-pointa.cn);pointa.cn+=dist;pointb.cn-=dist;

void deplace(int i,int j,double delta,point *coins) {
  double d;
  CLOSER(coins[i],coins[j],x,d,delta);
  CLOSER(coins[i],coins[j],y,d,delta);
}

void restreint(int *x,int *y,int tx,int ty) {
  if(*x<0) *x=0;
  if(*y<0) *y=0;
  if(*x>=tx) *x=tx-1;
  if(*y>=ty) *y=ty-1;
}

int check_zooms_dir(int student, char *zooms_dir=NULL,int log=0) {
  int ok=1;
  struct stat zd;
  
  if(student>=0) {
    if(stat(zooms_dir,&zd)!=0) {
      if(errno==ENOENT) {
	if(mkdir(zooms_dir,0755)!=0) {
	  ok=0;
	  printf("! ZOOMDC : Zoom dir creation error %d : %s\n",errno,zooms_dir);
	} else {
	  printf(": Zoom dir created %s\n",zooms_dir);
	}
      } else {
	ok=0;
	printf("! ZOOMDS : Zoom dir stat error %d : %s\n",errno,zooms_dir);
      }
    } else {
      if(!S_ISDIR(zd.st_mode)) {
	ok=0;
	printf("! ZOOMDP : Zoom dir is not a directory : %s\n",zooms_dir);
      }
    }	  
  } else {
    ok=0;
    if(log) {
      printf(": No zoom dir to create (student<0).\n");
    }
  }
  return(ok);
}

void mesure_case(IplImage *src,IplImage *illustr,
		 int student,int page,int question, int answer,
		 double prop,point *coins,IplImage *dst=NULL,
		 char *zooms_dir=NULL,int view=0) {
  int npix,npixnoir,xmin,xmax,ymin,ymax,x,y;
  int z_xmin,z_xmax,z_ymin,z_ymax;
  ligne lignes[4];
  int i,ok;
  double delta;

  int tx=src->width;
  int ty=src->height;

  CvPoint coins_int[4];

  static char* zoom_file=NULL;

#if OPENCV_20
  static int save_options[3]={CV_IMWRITE_PNG_COMPRESSION,7,0};
#endif

  npix=0;
  npixnoir=0;

  if(illustr!=NULL) {
    for(int i=0;i<4;i++) {
      coins_int[i].x=(int)coins[i].x;
      coins_int[i].y=(int)coins[i].y;
    }
    for(int i=0;i<4;i++) {
      cvLine(illustr,coins_int[i],coins_int[(i+1)%4],BLEU,1,CV_AA);
    }

    /* bounding box for zoom */
    z_xmin=tx-1;
    z_xmax=0;
    z_ymin=ty-1;
    z_ymax=0;
    for(int i=0;i<4;i++) {
      if(coins_int[i].x<z_xmin) z_xmin=coins_int[i].x;
      if(coins_int[i].x>z_xmax) z_xmax=coins_int[i].x;
      if(coins_int[i].y<z_ymin) z_ymin=coins_int[i].y;
      if(coins_int[i].y>z_ymax) z_ymax=coins_int[i].y;
    }

    /* a little bit larger... */
    int delta=(z_xmax-z_xmin + z_ymax-z_ymin)/20;
    z_xmin-=delta;
    z_ymin-=delta;
    z_xmax+=delta;
    z_ymax+=delta;
  }

  /* box reduction */
  delta=(1-prop)/2;
  deplace(0,2,delta,coins);
  deplace(1,3,delta,coins);

  /* output points used for mesuring */
  for(i=0;i<4;i++) {
    printf("COIN %.3f,%.3f\n",coins[i].x,coins[i].y);
  }

  if(view==1 || illustr!=NULL) {
    for(int i=0;i<4;i++) {
      coins_int[i].x=(int)coins[i].x;
      coins_int[i].y=(int)coins[i].y;
    }
  }
#ifdef OPENCV_21
  if(view==1) {
    for(int i=0;i<4;i++) {
      cvLine(dst,coins_int[i],coins_int[(i+1)%4],CV_RGB(255,255,255),1,CV_AA);
    }
  }
#endif
  if(illustr!=NULL) {
    for(int i=0;i<4;i++) {
      cvLine(illustr,coins_int[i],coins_int[(i+1)%4],ROSE,1,CV_AA);
    }

    /* making zoom */

    if(zooms_dir!=NULL && student>=0) {

      /* check if directory is present, or ceate it */
      ok=check_zooms_dir(student,zooms_dir,0);

      /* save zoom file */
      if(ok) {
	if(asprintf(&zoom_file,"%s/%d-%d.png",zooms_dir,question,answer)>0) {
	  printf(": Saving zoom to %s\n",zoom_file);
	  printf(": Z=(%d,%d)+(%d,%d)\n",
		 z_xmin,z_ymin,z_xmax-z_xmin,z_ymax-z_ymin);
	  cvSetImageROI(illustr,
			cvRect(z_xmin,z_ymin,z_xmax-z_xmin,z_ymax-z_ymin));
	  if(cvSaveImage(zoom_file,illustr
#if OPENCV_20
			 ,save_options
#endif
			 )!=1) {
	    printf("! ZOOMS : Zoom save error\n");
	  } else {
	    printf("ZOOM %d-%d.png\n",question,answer);
	  }
	  
	  cvResetImageROI(illustr);
	} else {
	  printf("! ZOOMFN : Zoom file name error\n");
	}
      }
    }
  }

  /* bounding box */
  xmin=tx-1;
  xmax=0;
  ymin=ty-1;
  ymax=0;
  for(i=0;i<4;i++) {
    if(coins[i].x<xmin) xmin=(int)coins[i].x;
    if(coins[i].x>xmax) xmax=(int)coins[i].x;
    if(coins[i].y<ymin) ymin=(int)coins[i].y;
    if(coins[i].y>ymax) ymax=(int)coins[i].y;
  }

  /* half planes equations */
  calcule_demi_plan(&coins[0],&coins[1],&lignes[0]);
  calcule_demi_plan(&coins[1],&coins[2],&lignes[1]);
  calcule_demi_plan(&coins[2],&coins[3],&lignes[2]);
  calcule_demi_plan(&coins[3],&coins[0],&lignes[3]);
      
  restreint(&xmin,&ymin,tx,ty);
  restreint(&xmax,&ymax,tx,ty);

  for(x=xmin;x<=xmax;x++) {
    for(y=ymin;y<=ymax;y++) {
      ok=1;
      for(i=0;i<4;i++) {
	if(evalue_demi_plan(&lignes[i],(double)x,(double)y)==0) ok=0;
      }
      if(ok==1) {
	npix++;
	if(PIXEL(src,x,y)) npixnoir++;
      }
    }
  }
      
  printf("PIX %d %d\n",npixnoir,npix);
}

int main( int argc, char** argv )
{
  if(!setlocale(LC_ALL,"POSIX")) {
    printf("! LOCALE : setlocale failed\n");
  }

  double threshold=0.6;
  double taille_orig_x=0;
  double taille_orig_y=0;
  double dia_orig=0;
  double tol_plus=0;
  double tol_moins=0;

  double prop,xmin,xmax,ymin,ymax;
  double coins_x[4],coins_y[4];
  double coins_x0[4],coins_y0[4];
  double tmp;
  int upside_down;
  int i;
  int student,page,question,answer;
  point box[4];
  linear_transform transfo;
  double mse;

  IplImage* src=NULL;
  IplImage* dst=NULL;
  IplImage* illustr=NULL;
  IplImage* src_calage=NULL;

  char *scan_file=NULL;
  char *out_image_file=NULL;
  char *zooms_dir=NULL;
  int view=0;
  int post_process_image=0;
  int ignore_red=0;

#if OPENCV_20
  int save_options[3]={CV_IMWRITE_JPEG_QUALITY,75,0};
#endif

  // Options
  // -x tx : gives the width of the original subject
  // -y ty : gives the height of the opriginal subject
  // -d d  : gives the diameter of the corner marks on the original subject
  // -p dp : gives the tolerance above mark diameter (fraction of the diameter)
  // -m dm : gives the tolerance below mark diameter
  // -t th : gives the threshold to convert to black&white
  // -o file : gives output file name for detected layout report image
  // -v / -P : asks for marks detection debugging image report

  char c;
  while ((c = getopt (argc, argv, "x:y:d:i:p:m:t:o:vPr")) != -1) {
    switch (c) {
    case 'x': taille_orig_x=atof(optarg);break; 
    case 'y': taille_orig_y=atof(optarg);break; 
    case 'd': dia_orig=atof(optarg);break; 
    case 'p': tol_plus=atof(optarg);break;
    case 'm': tol_moins=atof(optarg);break;
    case 't': threshold=atof(optarg);break;
    case 'o': out_image_file=strdup(optarg);break;
    case 'v': view=1;break;
    case 'r': ignore_red=1;break;
    case 'P': post_process_image=1;view=2;break;
    }
  }

  printf("TX=%.2f TY=%.2f DIAM=%.2f\n",taille_orig_x,taille_orig_y,dia_orig);

  size_t commande_t;
  char* commande=NULL;
  char* endline;
  char text[128];

  CvPoint textpos;
  CvFont font;
  double fh;

  while(getline(&commande,&commande_t,stdin)>=6) {
    //printf("LC_NUMERIC: %s\n",setlocale(LC_NUMERIC,NULL));

    if((endline=strchr(commande,'\r'))) *endline='\0';
    if((endline=strchr(commande,'\n'))) *endline='\0';
    if(strncmp(commande,"output ",7)==0) {
      free(out_image_file);
      out_image_file=strdup(commande+7);
    } else if(strncmp(commande,"zooms ",6)==0) {
      free(zooms_dir);
      zooms_dir=strdup(commande+6);
    } else if(strncmp(commande,"load ",5)==0) {
      free(scan_file);
      scan_file=strdup(commande+5);

      if(out_image_file != NULL &&
	 !post_process_image) {
	illustr=cvLoadImage(scan_file, CV_LOAD_IMAGE_COLOR);
	if(illustr==NULL) {
	  printf("! LOAD : Error loading scan file with color mode [%s]\n",scan_file);
	} else {
	  if(illustr->origin==1) {
	    printf(": Image flip\n");
	    cvFlip(illustr,NULL,0);
	  }
	}
      }

      load_image(&src,scan_file,ignore_red,threshold,view);

      src_calage=cvCloneImage(src);
      calage(src_calage,illustr,
	     taille_orig_x,taille_orig_y,
	     dia_orig,
	     tol_plus, tol_moins,
	     coins_x,coins_y,
	     &dst,view);
      upside_down=0;
      
      if(out_image_file != NULL && illustr==NULL) {
	illustr=dst;
	dst=NULL;
      }
      
      cvReleaseImage(&src_calage);

    } else if((sscanf(commande,"optim %lf,%lf %lf,%lf %lf,%lf %lf,%lf",
		      &coins_x0[0],&coins_y0[0],
		      &coins_x0[1],&coins_y0[1],
		      &coins_x0[2],&coins_y0[2],
		      &coins_x0[3],&coins_y0[3])==8)
	      || (strncmp(commande,"reoptim",7)==0) ) {
      /* "optim" and 8 arguments: 4 marks positions (x y,
	  order: UL UR BR BL)
	  return: optimal linear transform and MSE */
      /* "reoptim": optim with the same arguments as for last "optim" call */
      mse=optim(coins_x0,coins_y0,coins_x,coins_y,4,&transfo);
      printf("Transfo:\na=%f\nb=%f\nc=%f\nd=%f\ne=%f\nf=%f\n",
	     transfo.a,transfo.b,
	     transfo.c,transfo.d,
	     transfo.e,
	     transfo.f);
      printf("MSE=%f\n",mse);
    } else if(strncmp(commande,"rotateOK",8)==0) {
      /* validates upside down rotation */
      if(upside_down) {
	transfo.a=-transfo.a;
	transfo.b=-transfo.b;
	transfo.c=-transfo.c;
	transfo.d=-transfo.d;
	transfo.e=(src->width-1)-transfo.e;
	transfo.f=(src->height-1)-transfo.f;
	
	if(src!=NULL) cvFlip(src,NULL,-1);
	if(illustr!=NULL) cvFlip(illustr,NULL,-1);
	if(dst!=NULL) cvFlip(dst,NULL,-1);

	for(i=0;i<4;i++) {
	  coins_x[i]=(src->width-1)-coins_x[i];
	  coins_y[i]=(src->height-1)-coins_y[i];
	}

	upside_down=0;

	printf("Transfo:\na=%f\nb=%f\nc=%f\nd=%f\ne=%f\nf=%f\n",
	       transfo.a,transfo.b,
	       transfo.c,transfo.d,
	       transfo.e,
	       transfo.f);
      }
    } else if(strncmp(commande,"rotate180",9)==0) {
      for(i=0;i<2;i++) {
	SWAP(coins_x[i],coins_x[i+2],tmp);
	SWAP(coins_y[i],coins_y[i+2],tmp);
      }
      upside_down=1-upside_down;
      printf("UpsideDown=%d\n",upside_down);
    } else if(sscanf(commande,"id %d %d %d %d",
		     &student,&page,&question,&answer)==4) {
      /* box id */
    } else if(sscanf(commande,"mesure0 %lf %lf %lf %lf %lf",
		     &prop,
		     &xmin,&xmax,&ymin,&ymax)==5) {
      /* "mesure0" and 5 arguments: proportion, xmin, xmax, ymin, ymax
	 return: number of black pixels and total number of pixels */
      transforme(&transfo,xmin,ymin,&box[0].x,&box[0].y);
      transforme(&transfo,xmax,ymin,&box[1].x,&box[1].y);
      transforme(&transfo,xmax,ymax,&box[2].x,&box[2].y);
      transforme(&transfo,xmin,ymax,&box[3].x,&box[3].y);
      mesure_case(src,illustr,
		  student,page,question,answer,
		  prop,box,dst,zooms_dir,view);
      student=-1;
    } else if(sscanf(commande,"mesure %lf %lf %lf %lf %lf %lf %lf %lf %lf",
		     &prop,
		     &box[0].x,&box[0].y,
		     &box[1].x,&box[1].y,
		     &box[2].x,&box[2].y,
		     &box[3].x,&box[3].y)==9) {
      /* "mesure" and 9 arguments: proportion, and 4 vertices
	 (x y, order: UL UR BR BL)
	 returns: number of black pixels and total number of pixels */
      mesure_case(src,illustr,
		  student,page,question,answer,
		  prop,box,dst,zooms_dir,view);
      student=-1;
    } else if(strlen(commande)<100 && 
	      sscanf(commande,"annote %s",text)==1) {
      fh=src->height/50.0;
      cvInitFont(&font,CV_FONT_HERSHEY_PLAIN,fh/14,fh/14,0.0,1+(int)(fh/20),CV_AA);
      textpos.y=(int)(1.6*fh);textpos.x=10;
      cvPutText(illustr,text,textpos,&font,BLEU);
    } else {
      printf(": %s\n",commande);
      printf("! SYNERR : Syntax error\n");
    }

    printf("__END__\n");
    fflush(stdout);
  }

#ifdef OPENCV_21
  if(view==1) {
    cvNamedWindow( "Source", CV_WINDOW_NORMAL );
    cvShowImage( "Source", src );
    cvNamedWindow( "Components", CV_WINDOW_NORMAL );
    cvShowImage( "Components", dst );
    cvWaitKey(0);

    cvReleaseImage(&dst);
  }
#endif

  if(illustr && strlen(out_image_file)>1) {
    if(cvSaveImage(out_image_file,illustr
#if OPENCV_20
		   ,save_options
#endif
		   )!=1) {
      printf("! LAYS : Layout image save error\n");
    }
  }

  cvReleaseImage(&illustr);
  cvReleaseImage(&src);

  free(commande);
  free(scan_file);

  return(0);
}
    
