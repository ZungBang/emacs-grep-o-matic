;;; grep-o-matic.el --- auto grep word under cursor

;; Copyright (C) 2008-2012 Avi Rozen

;; Author: Avi Rozen <avi.rozen@gmail.com>
;; Keywords: tools, processes, search
;; URL: https://github.com/ZungBang/emacs-grep-o-matic
;; Version: 1.0.4

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; This package lets the user launch a search, with a single key combination,
;; for the word under the cursor, in the current repository, or the current
;; directory, or in the set of currently open files.
;;
;; Works nicely in combination with grep-a-lot and repository-root libraries.
;;
;; Installation:
;;
;; 1. Put this file in a directory that is a member of load-path, and
;;    byte-compile it (e.g. with `M-x byte-compile-file') for better
;;    performance.
;; 2. Add the following to your ~/.emacs:
;;    ;(require 'repository-root) ; optional: needed for repository-wide search
;;    (require 'grep-o-matic)
;; 3. Customize grep-o-matic with `M-x customize-group grep-o-matic'
;;
;; Repository-wide search requires customization of the repository root function,
;; unless the repository-root libarary is loaded before grep-o-matic.
;;
;; Default Key Bindings:
;;
;; M-] M-/         Search for current word in current repository
;; M-] M-.         Search for current word in current directory (recursive)
;; M-] M-,         Search for current word in currently opened files
;;                 Prefix these with C-u to edit the search regexp 
;;

;;; Code:

(require 'grep)

(defgroup grep-o-matic nil
  "Automation layer for grep.el"
  :group 'grep
  :group 'convenience
  :prefix "grep-o-matic-")


(defcustom grep-o-matic-search-patterns
  (list "*.cpp" "*.c" "*.h" "*.awk" "*.sh" "*.py" "*.pl" "[Mm]akefile" "*.el")
  "*Search file patterns for use with grep-o-matic-* commands."
  :group 'grep-o-matic
  :type '(repeat string))

(defcustom grep-o-matic-repository-root-function (if (featurep 'repository-root)
                                                     'repository-root
                                                   nil)
  "*If non-nil, a function that returns the current file's repository root directory.
The function is called with a single string argument (a file name) and should
return either nil, or a string, which is the root directory of that file's repository.
The default value is nil, unless the repository-root library is loaded before
loading grep-o-matic, in which case the default value is `repository-root'."
  :group 'grep-o-matic
  :type '(choice (const nil) (function)))

(defcustom grep-o-matic-ask-about-save t
  "*If non-nil ask which buffers to save before performing a search.
Otherwise, all modified buffers are saved without asking."
  :group 'grep-o-matic
  :type 'boolean)

(defun grep-o-matic-repository-root (filename)
  "Attempt to deduce the current file's repository root directory.
You should customize `grep-o-matic-repository-root-function' and provide a function that
does the actual work, based of the type of SCM tool that you're using."
  (if (null filename)
      nil
    (let* ((directory (file-name-directory filename))
           (repository-root (if (and grep-o-matic-repository-root-function
                                     (functionp grep-o-matic-repository-root-function))
                                (apply grep-o-matic-repository-root-function (list filename))
                              nil)))
      (or repository-root directory))))

(defun grep-o-matic-get-regexp (prompt)
  "Get the default regexp or query the user for it."
  (let ((regexp (grep-tag-default)))
    (if (and (not prompt) regexp)
	(progn
	  (add-to-list 'grep-regexp-history regexp)
	  regexp)
      (grep-read-regexp))))

(defun grep-o-matic-directory (prompt directory)
  "Search directory for word at point.
Optionaly prompt for regexp to search."
  (let ((patterns grep-o-matic-search-patterns)
	(extension (if buffer-file-name
		       (file-name-extension buffer-file-name)
		     nil))
	(filename (if buffer-file-name
		      (file-name-nondirectory buffer-file-name)
		    nil)))
    (let ((nomatch (or (null filename)
		       (and filename
			    (let ((head (car patterns))
				  (tail (cdr patterns)))
			      (while (and (not (null head))
					  (not (string-match (wildcard-to-regexp head) filename)))
				(progn
				  (setq head (car tail))
				  (setq tail (cdr tail))))
			      (null head))))))
      ;; if current file does not match search patterns then select a default pattern
      (when nomatch
	(setq patterns (list (if extension
				 (concat "*." extension)
			       "*"))))
      (grep-compute-defaults)
      (save-some-buffers (not grep-o-matic-ask-about-save) nil)
      (rgrep (grep-o-matic-get-regexp prompt)
	     (mapconcat (lambda (s) s) patterns " ")
	     (if directory
		 directory
	       default-directory)))))

(defun grep-o-matic-repository (&optional prompt)
  "Search repository for word at point.
Optionaly prompt for regexp to search."
  (interactive "P")
  (grep-o-matic-directory prompt (grep-o-matic-repository-root buffer-file-name)))

(defun grep-o-matic-current-directory (&optional prompt)
  "Search current directory for word at point.
Optionaly prompt for regexp to search."
  (interactive "P")
  (grep-o-matic-directory prompt (if buffer-file-name
                                     (file-name-directory buffer-file-name)
                                   nil)))

(defun grep-o-matic-visited-files (&optional prompt)
  "Search currently visited files for word at point.
Optionaly prompt for regexp to search."
  (interactive "P")
  (let ((regexp (grep-o-matic-get-regexp prompt))
        (files (let ((directory-abbrev-alist
                      (cons (cons (regexp-quote (expand-file-name default-directory)) "./") directory-abbrev-alist)))
                 (mapconcat (lambda (fn) (abbreviate-file-name (shell-quote-argument fn)))
                            (apply 'nconc
                                   (mapcar '(lambda (buffer)
                                              (let ((file (buffer-file-name buffer)))
                                                (if (and file
                                                         (cond ((featurep 'ange-ftp)
                                                                (not (ange-ftp-ftp-name file)))
                                                               ((featurep 'efs)
                                                                (not (efs-ftp-path file)))
                                                               (t t)))
                                                    (list file))))
                                           (buffer-list)))
                            " ")))
        (dir "")
        (excl ""))
    (progn
      (grep-compute-defaults)
      (save-some-buffers (not compilation-ask-about-save) nil)
      (grep (grep-expand-template grep-template regexp files dir excl)))))

;; key bindings
(define-prefix-command 'grep-o-matic-map)
(define-key grep-o-matic-map "\M-/" 'grep-o-matic-repository)
(define-key grep-o-matic-map "/" 'grep-o-matic-repository)
(define-key grep-o-matic-map "\M-." 'grep-o-matic-current-directory)
(define-key grep-o-matic-map "." 'grep-o-matic-current-directory)
(define-key grep-o-matic-map "\M-," 'grep-o-matic-visited-files)
(define-key grep-o-matic-map "," 'grep-o-matic-visited-files)
(global-set-key "\M-]" 'grep-o-matic-map)

(provide 'grep-o-matic)

;;; grep-o-matic.el ends here
