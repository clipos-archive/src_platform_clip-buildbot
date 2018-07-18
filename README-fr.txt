ARCHITECTURE:

3 etages etanches
export log est fait sous forme d'un process dedié.

-------------      --------------         ---------------
|   Poller  |------>  Compile     ----->[[   export log   ]]
-------------      --------------         ---------------
  MAJ mirroir        lxc-sdk compile          inotify commit log
  local

TODO: 
-Gestion des mots de passes SVN chiffrés en pas stockés par svn
-Implantation d'un backend de commit des log

INCOMING
-lecture des fichiers specs dans les container lxc pour determiner l'ensemble des especes a laquelle appartient un paquet et lancer la compilation pour chauquye espece pour verifier qu'avec tous les set de usefalgs cela compile
