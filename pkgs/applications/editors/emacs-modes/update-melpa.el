;; -*- lexical-binding: t -*-

;; This is the updater for recipes-archive-melpa.json

(require 'promise)
(require 'url)
(require 'json)
(require 'cl)
(require 'subr-x)
(require 'seq)

;; # Lib

(defun alist-set (key value alist)
  (cons
   (cons key value)
   (assq-delete-all
    key alist)))

(defun alist-update (key f alist)
  (let ((value (alist-get key alist)))
    (cons
     (cons key (funcall f value))
     (assq-delete-all
      key alist))))

;; ## Monkey Patch finally, see https://github.com/chuntaro/emacs-promise/pull/6

(cl-defmethod promise-finally ((this promise-class) f)
  (promise-then this
                (lambda (value)
                  (promise-then (promise-resolve (funcall f))
                                (lambda (_) value)))
                (lambda (err)
                  (promise-then (promise-resolve (funcall f))
                                (lambda (_) (promise-reject err))))))

(defun log-promise (p)
  (promise-new
   (lambda (resolve reject)
     (promise-then
      p
      (lambda (res) (message "Result: %s" res) (funcall resolve res))
      (lambda (err) (message "Error: %s" err) (funcall reject err))))))

;; ## Semaphore implmentation

;; This is used to control parallelism in fetcher and indexer

(defclass semaphore ()
  ((-name :initarg :name)
   (-available :initarg :available)
   (-acquired :initform 0)
   (-released :initform 0)
   (-mutex :type mutex)
   (-cvar :type condition-variable)))

(cl-defmethod initialize-instance :after ((inst semaphore) &rest args)
  (with-slots (-name) inst
    (let ((mutex (make-mutex -name)))
      (oset inst -mutex mutex)
      (oset inst -cvar (make-condition-variable mutex -name)))))

(defun make-semaphore (count &optional name)
  (make-instance 'semaphore
                 :name name
                 :available count))

(cl-defmethod semaphore-acquire ((this semaphore))
  (with-slots (-available -mutex -cvar) this
    (with-mutex -mutex
      (while (with-slots (-acquired -released) this
               (>= -acquired (+ -available -released)))
        (condition-wait -cvar))
      (with-slots (-acquired) this
        (oset this -acquired (+ 1 -acquired))))))

(cl-defmethod semaphore-release ((this semaphore))
  (with-slots (-available -mutex -cvar) this
    (with-mutex -mutex
      (condition-notify -cvar)
      (with-slots (-released) this
        (oset this -released (+ 1 -released))))))

;; ## Resolve handler on separate thread

(defun thread-promise (f &rest args)
  (promise-new
   (lambda (resolve reject)
     (make-thread
      (lambda ()
        (condition-case ex
            (funcall resolve (apply f args))
          (error (funcall reject ex))))))))

;; ## Resolve handler, gated by semaphore

(defun promise-new-pipelined (semaphore handler)
  (if semaphore
      (promise-finally
       (promise-new
        (lambda (resolve reject)
          (semaphore-acquire semaphore)
          (funcall handler resolve reject)))
       (lambda ()
         (semaphore-release semaphore)))
    (promise-new handler)))

;; ## Promise the output of process

(defun maybe-message (msg)
  (when (not (string-empty-p msg))
    (message msg)))

(defun process-promise (semaphore program &rest args)
  "Generate an asynchronous process and
return Promise to resolve in that process."
  (promise-new-pipelined
   semaphore
   (lambda (resolve reject)
     (let* ((stdout (generate-new-buffer (concat "*" program "-stdout*")))
            (stderr (generate-new-buffer (concat "*" program "-stderr*")))
            (stderr-pipe (make-pipe-process
                          :name (concat "*" program "-stderr-pipe*")
                          :noquery t
                          :filter (lambda (_ output)
                                    (with-current-buffer stderr
                                      (insert output))))))
       (condition-case err
           (make-process :name program
                         :buffer stdout
                         :command (cons program args)
                         :stderr stderr-pipe
                         :sentinel (lambda (process event)
                                     (unwind-protect
                                         (let ((stderr-str (with-current-buffer stderr
                                                             (string-trim-right (buffer-string))))
                                               (stdout-str (with-current-buffer stdout
                                                             (string-trim-right (buffer-string)))))
                                           (if (string= event "finished\n")
                                               (progn
                                                 (maybe-message stderr-str)
                                                 (funcall resolve stdout-str))
                                             (progn
                                               (maybe-message stdout-str)
                                               (maybe-message stderr-str)
                                               (funcall reject (list event stderr-str)))))
                                       (delete-process stderr-pipe)
                                       (kill-buffer stdout)
                                       (kill-buffer stderr))))
         (error (delete-process stderr-pipe)
                (kill-buffer stdout)
                (kill-buffer stderr)
                (signal (car err) (cdr err))))))))

;; ## Shell promise + env

(defun as-string (o)
  (with-output-to-string (princ o)))

(defun assocenv (env &rest namevals)
  (let ((process-environment (copy-sequence env)))
    (mapc (lambda (e)
            (setenv (as-string (car e))
                    (cadr e)))
          (seq-partition namevals 2))
    process-environment))

(defun shell-promise (semaphore env script)
  (let ((process-environment env))
    (process-promise semaphore shell-file-name shell-command-switch script)))

;; # Updater

;; ## Previous Archive Reader

(defun previous-commit (index ename)
  (when index
    (when-let (desc (gethash ename index))
      (gethash 'commit desc))))

(defun previous-sha256 (index ename)
  (when index
    (when-let (desc (gethash ename index))
      (gethash 'sha256 desc))))

(defun parse-previous-archive (filename)
  (let ((idx (make-hash-table :test 'equal)))
    (loop for desc in
          (let ((json-object-type 'hash-table)
                (json-array-type 'list)
                (json-key-type 'symbol))
            (json-read-file filename))
          do (puthash (gethash 'ename desc)
                      desc idx))
    idx))

;; ## Prefetcher

;; (defun latest-git-revision (url)
;;   (process-promise "git" "ls-remote" url))

(defun prefetch (semaphore fetcher name repo commit)
  (promise-then
   (apply 'process-promise
          semaphore
          (pcase fetcher
            ("github"    (list "nix-prefetch-url"
                               "--name"   name
                               "--unpack" (concat "https://github.com/" repo "/archive/" commit ".tar.gz")))
            ("gitlab"    (list "nix-prefetch-url"
                               "--name"   name
                               "--unpack" (concat "https://gitlab.com/" repo "/repository/archive.tar.gz?ref=" commit)))
            ("bitbucket" (list "nix-prefetch-hg"
                               (concat "https://bitbucket.com/" repo) commit))
            ("hg"        (list "nix-prefetch-hg"
                               repo commit))
            ("git"       (list "nix-prefetch-git"
                               "--fetch-submodules"
                               "--url" repo
                               "--rev" commit))
            (_           (throw 'unknown-fetcher fetcher))))
   (lambda (res)
     (pcase fetcher
       ("git" (alist-get 'sha256 (json-read-from-string res)))
       (_ (car (split-string res)))))))

(defun append-fetched-info (info recipe-index-promise ename sha256)
  (promise-then
   recipe-index-promise
   (lambda (idx)
     (if-let (desc (gethash ename idx))
         (destructuring-bind (rcp-commit . rcp-sha256) desc
           (append `((sha256  . ,sha256)
                     (recipeCommit . ,rcp-commit)
                     (recipeSha256 . ,rcp-sha256))
                   info))
       (append `((sha256  . ,sha256)
                 (error . "No recipe info"))
               info)))))

(defun start-fetch (semaphore recipe-index-promise recipes archive previous)
  (promise-all
   (mapcar (lambda (entry)
             (let* ((esym    (car entry))
                    (ename   (symbol-name esym))
                    (eprops  (cdr entry))
                    (aentry  (gethash esym archive))
                    (aprops  (and aentry (gethash 'props aentry)))
                    (version (and aentry (gethash 'ver aentry)))

                    (fetcher (alist-get 'fetcher eprops))
                    (repo    (alist-get 'repo eprops))

                    (base-result `((ename   . ,ename)
                                   (version . ,version)
                                   (fetcher . ,fetcher)
                                   (repo    . ,repo))))
               (if aprops
                   (let* ((url     (or (gethash 'url aprops)
                                       (alist-get 'url eprops)))
                          (deps    (when-let (deps (gethash 'deps aentry))
                                     (remove 'emacs (hash-table-keys deps))))
                          (commit  (gethash 'commit aprops))
                          (prev-commit (previous-commit previous ename))
                          (prev-sha256 (previous-sha256 previous ename))
                          
                          (archive-result (append base-result
                                                  `((url     . ,url)
                                                    (commit  . ,commit)
                                                    (deps    . ,(sort deps 'string<))))))
                     (if (and commit prev-sha256
                              (equal prev-commit commit))
                         (progn
                           (message "INFO: %s: re-using %s %s" ename prev-commit prev-sha256)
                           (append-fetched-info archive-result recipe-index-promise ename prev-sha256))
                       (if (and commit (or repo url))
                           (promise-then
                            (prefetch semaphore fetcher ename (or repo url) commit)
                            (lambda (sha256)
                              (message "INFO: %s: prefetched repository %s %s" ename commit sha256)
                              (append-fetched-info archive-result recipe-index-promise ename sha256))
                            (lambda (err)
                              (message "ERROR: %s: during prefetch %s" ename err)
                              (cons `(error . ,err)
                                    archive-result)))
                         (progn
                           (message "ERROR: %s: no commit information" ename)
                           (promise-resolve (cons `(error . "No commit information")
                                                  archive-result))))))
                 (progn
                   (message "ERROR: %s: not in archive" ename)
                   (promise-resolve (cons `(error . "Not in archive")
                                          base-result))))))
           recipes)))

;; ## Emitter

(defun emit-json (prefetch-semaphore recipe-index-promise recipes archive previous)
  (promise-then
   (start-fetch
    prefetch-semaphore
    recipe-index-promise
    (sort recipes (lambda (a b)
                    (string-lessp
                     (symbol-name (car a))
                     (symbol-name (car b)))))
    archive
    previous)
   (lambda (descriptors)
     (message "Finished downloading %d descriptors" (length descriptors))
     (let ((buf (generate-new-buffer "*recipes-archive*")))
       (with-current-buffer buf
         ;; (switch-to-buffer buf)
         ;; (json-mode)
         (insert
          (let ((json-encoding-pretty-print t)
                (json-encoding-default-indentation " "))
            (json-encode descriptors)))
         buf)))))

;; ## Recipe indexer

(defun http-get (url parser)
  (promise-new
   (lambda (resolve reject)
     (url-retrieve
      url (lambda (status)
            (funcall resolve (condition-case err
                                 (progn
                                   (goto-char (point-min))
                                   (search-forward "\n\n")
                                   (message (buffer-substring (point-min) (point)))
                                   (delete-region (point-min) (point))
                                   (funcall parser))
                               (funcall reject err))))))))

(defun json-read-buffer (buffer)
  (with-current-buffer buffer
    (save-excursion
      (mark-whole-buffer)
      (json-read))))

(defun error-count (recipes-archive)
  (length
   (seq-filter
    (lambda (desc)
      (alist-get 'error desc))
    recipes-archive)))

;; (error-count (json-read-buffer "recipes-archive-melpa.json"))

(defun latest-recipe-commit (semaphore repo base-rev recipe)
  (shell-promise
   semaphore (assocenv process-environment
                       "GIT_DIR" repo
                       "BASE_REV" base-rev
                       "RECIPE" recipe)
   "exec git log --first-parent -n1 --pretty=format:%H $BASE_REV -- recipes/$RECIPE"))

(defun latest-recipe-sha256 (semaphore repo base-rev recipe)
  (promise-then
   (shell-promise
    semaphore (assocenv process-environment
                        "GIT_DIR" repo
                        "BASE_REV" base-rev
                        "RECIPE" recipe)
    "exec nix-hash --flat --type sha256 --base32 <(
       git cat-file blob $(
         git ls-tree $BASE_REV recipes/$RECIPE | cut -f1 | cut -d' ' -f3
       )
     )")
   (lambda (res)
     (car
      (split-string res)))))

(defun index-recipe-commits (semaphore repo base-rev recipes)
  (promise-then
   (promise-all
    (mapcar (lambda (recipe)
              (promise-then
               (latest-recipe-commit semaphore repo base-rev recipe)
               (let ((sha256p (latest-recipe-sha256 semaphore repo base-rev recipe)))
                 (lambda (commit)
                   (promise-then sha256p
                                 (lambda (sha256)
                                   (message "Indexed Recipe %s %s %s" recipe commit sha256)
                                   (cons recipe (cons commit sha256))))))))
            recipes))
   (lambda (rcp-commits)
     (let ((idx (make-hash-table :test 'equal)))
       (mapc (lambda (rcpc)
               (puthash (car rcpc) (cdr rcpc) idx))
             rcp-commits)
       idx))))

(defun with-melpa-checkout (resolve)
  (let ((tmpdir (make-temp-file "melpa-" t)))
    (promise-finally
     (promise-then
      (shell-promise
       (make-semaphore 2)
       (assocenv process-environment "MELPA_DIR" tmpdir)
       "cd $MELPA_DIR
       (git init --bare
        git remote add origin https://github.com/melpa/melpa.git
        git fetch origin) 1>&2
       echo -n $MELPA_DIR")
      (lambda (dir)
        (message "Created melpa checkout %s" dir)
        (funcall resolve dir)))
     (lambda ()
       (delete-directory tmpdir t)
       (message "Deleted melpa checkout %s" tmpdir)))))

(defun list-recipes (repo base-rev)
  (promise-then
   (shell-promise nil (assocenv process-environment
                                "GIT_DIR" repo
                                "BASE_REV" base-rev)
                  "git ls-tree --name-only $BASE_REV recipes/")
   (lambda (s)
     (mapcar (lambda (n)
               (substring n 8))
             (split-string s)))))

;; ## Main runner

(defvar recipe-indexp)
(defvar archivep)

(defun run-updater ()
  (message "Turning off logging to *Message* buffer")
  (setq message-log-max nil)
  (setenv "GIT_ASKPASS")
  (setenv "SSH_ASKPASS")
  (setq process-adaptive-read-buffering nil)
  
  ;; Indexer and Prefetcher run in parallel

  ;; Recipe Indexer
  (setq recipe-indexp
        (with-melpa-checkout
         (lambda (repo)
           (promise-then
            (promise-then
             (list-recipes repo "origin/master")
             (lambda (recipe-names)
               (thread-promise 'index-recipe-commits
                               ;; The indexer runs on a local git repository,
                               ;; so it is CPU bound.
                               ;; Adjust for core count + 2
                               (make-semaphore 6 "local-indexer")
                               repo "origin/master"
                               ;; (seq-take recipe-names 20)
                               recipe-names)))
            (lambda (res)
              (message "Indexed Recipes: %d" (hash-table-count res))
              (defvar recipe-index res)
              res)
            (lambda (err)
              (message "ERROR: %s" err))))))

  ;; Prefetcher + Emitter
  (setq archivep
        (promise-then
         (promise-then (promise-all
                        (list (http-get "https://melpa.org/recipes.json"
                                        (lambda ()
                                          (let ((json-object-type 'alist)
                                                (json-array-type 'list)
                                                (json-key-type 'symbol))
                                            (json-read))))
                              (http-get "https://melpa.org/archive.json"
                                        (lambda ()
                                          (let ((json-object-type 'hash-table)
                                                (json-array-type 'list)
                                                (json-key-type 'symbol))
                                            (json-read))))))
                       (lambda (resolved)
                         (message "Finished download")
                         (seq-let [recipes-content archive-content] resolved
                           ;; The prefetcher is network bound, so 64 seems a good estimate
                           ;; for parallel network connections
                           (thread-promise 'emit-json (make-semaphore 64 "prefetch-pool")
                                           recipe-indexp
                                           recipes-content
                                           archive-content
                                           (parse-previous-archive "recipes-archive-melpa.json")))))
         (lambda (buf)
           (with-current-buffer buf
             (write-file "recipes-archive-melpa.json")))
         (lambda (err)
           (message "ERROR: %s" err))))
  
  ;; Shutdown routine
  (make-thread
   (lambda ()
     (promise-finally archivep
                      (lambda ()
                        ;; (message "Joining threads %s" (all-threads))
                        ;; (mapc (lambda (thr)
                        ;;         (when (not (eq thr (current-thread)))
                        ;;           (thread-join thr)))
                        ;;       (all-threads))
                        
                        (kill-emacs 0))))))

