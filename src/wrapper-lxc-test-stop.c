// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2016-2018 ANSSI. All Rights Reserved.
#define _GNU_SOURCE
#include<stdlib.h>
#include<unistd.h>
int main(int argc, char **argv)
{
  int i;
  const char *prefix="sdk-test-";
  char *myargv[5]={"/usr/bin/lxc-stop","-n","dummy","-k",0};
  if(argc<1)
    	exit(1);
  for(i=0;i<9;i++)
    if(argv[1][i]!=prefix[i])
      exit(1);
  for(;argv[1][i]!=0;i++)
  {
    if(argv[1][i]<48) //avant chiffres
 	exit(1);
    if((argv[1][i]>57)&&(argv[1][i]<65))//apres chiffres avant maj
      exit(1);
    if((argv[1][i]>91)&&(argv[1][i]<95))//apres MAJ jusqu'a _
      exit(1);
    if(argv[1][i]==96)// backquote
      exit(1);
    if(argv[1][i]>123)//apres minuscules
      exit(1);
  }
  setresuid(0,0,0); 
  myargv[2]=argv[1];
  execve("/usr/bin/lxc-stop",myargv, NULL);
}
