(cl:in-package #:clostrum-basic)

;;; Function and variable entries.
(defclass function-entry ()
  ((name
    :initarg :name
    :reader name)
   ;; The CAR of the cell contains the function determined by the
   ;; entry.  The CDR of the cell contains a function that, when
   ;; called, signals an error.  When the function determined by the
   ;; entry is undefined, the CAR of the cell is the same as the CDR
   ;; of the cell.
   (cell
    :reader cell)
   ;; We do not check what client code puts in this slot.  Any non-NIL
   ;; value means that the name represents a special operator.  Some
   ;; clients might just store T in the slot.  Others might store a
   ;; function to be used for compiling a special form using the
   ;; operator.
   (special-operator
    :initform nil
    :accessor special-operator)
   (macro-function
    :initform nil
    :accessor macro-function)
   (compiler-macro-function
    :initform nil
    :accessor compiler-macro-function)
   (function-type
    :initform nil
    :accessor function-type)
   (function-inline
    :initform nil
    :accessor function-inline)
   (setf-expander
    :initform nil
    :accessor setf-expander))
  (:default-initargs :name (error "The initarg :NAME is required.")))

;;; Make sure NAME names a function entry in ENVIRONMENT.
;;; KEYWORD-ARGUMENTS are keyword/value pairs that will be passed
;;; either to MAKE-INSTANCE in order create a new entry if no entry
;;; exists, or will be passed to REINITIALIZE-INSTANCE to modify the
;;; existing entry if one does exist.  The existing entry or the entry
;;; being created is returned.
(defun ensure-function-entry (name environment &rest keyword-arguments)
  (let ((entry (function-entry name environment)))
    (if (null entry)
        (progn
          (setf entry
                (apply #'make-instance 'function-entry
                       :name name keyword-arguments))
          (setf (function-entry name environment)
                entry))
        (apply #'reinitialize-instance entry keyword-arguments))
    entry))

(defmethod initialize-instance :after ((instance function-entry) &key name)
  ;; We indicate that a function name is FUNBOUND by storing a
  ;; function in the CAR of the cell that, when called, signals an
  ;; UNDEFINED-FUNCTION error.  This way, there is no need for an
  ;; explicit test to verify that the name is FBOUND before calling
  ;; the function.  We store the same, as in EQ, function in the CDR
  ;; of the cell.  That way, testing whether the function is unbound
  ;; is an EQ comparison between the CAR and the CDR of the cell, and
  ;; FMAKUNBOUND is implemented by copying the CDR of the cell to the
  ;; CAR.
  (let ((unbound-function
          (lambda (&rest args)
            (declare (ignore args))
            (error 'undefined-function :name name))))
    (setf (slot-value instance 'cell)
          (cons unbound-function unbound-function))))

(defun function-bound-p (function-entry)
  (let ((cell (cell function-entry)))
    (not (eq (car cell) (cdr cell)))))

(defconstant +unbound+ 'unbound)

(defclass variable-entry ()
  ((name
    :initarg :name
    :reader name)
   ;; The CAR of the cell contains the value of the variable
   ;; determined by the entry.  The CDR of the cell contains a value
   ;; that indicates that the variable is unbound.  When the variable
   ;; is unbound, the CAR and the CDR contain the same value.  Since
   ;; CL:MAKUNBOUND (which should really be called something else like
   ;; MAKE-TO-HAVE-NO-VALUE) must take into account dynamic bindings
   ;; of the variable, we do not supply code for MAKUNBOUND here.  It
   ;; must be implemented by the client.
   (cell
    :reader cell
    :initform (cons +unbound+ +unbound+))
   ;; This slot contains a true value if and only if the entry
   ;; represents a constant variable.  The value of the constant
   ;; variable is then contained in the CAR of the CONS cell in the
   ;; slot CELL.
   (constant-variable-p
    :initform nil
    :accessor constant-variable-p)
   ;; This slot contains a true value if and only if the entry
   ;; represents a special variable.  The value of the constant
   ;; variable is then contained in the CAR of the CONS cell in the
   ;; slot CELL.
   (special-variable-p
    :initform nil
    :accessor special-variable-p)
   ;; This slot contains a true value if and only if hte entry
   ;; represents a symbol macro.  A function that, when called,
   ;; returns the expansion of the symbol macro is then contained in
   ;; the CAR of the CONS cell in the slot CELL.
   (symbol-macro-p
    :initform nil
    :accessor symbol-macro-p)
   (variable-type
    :initform nil
    :accessor variable-type)
   (type-expander
    :initform nil
    :accessor type-expander))
  (:default-initargs :name (error "The initarg :NAME is required.")))

;;; Make sure NAME names a variable entry in ENVIRONMENT.
;;; KEYWORD-ARGUMENTS are keyword/value pairs that will be passed
;;; either to MAKE-INSTANCE in order create a new entry if no entry
;;; exists, or will be passed to REINITIALIZE-INSTANCE to modify the
;;; existing entry if one does exist.  The existing entry or the entry
;;; being created is returned.
(defun ensure-variable-entry (name environment &rest keyword-arguments)
  (let ((entry (variable-entry name environment)))
    (if (null entry)
        (progn
          (setf entry
                (apply #'make-instance 'variable-entry
                       :name name keyword-arguments))
          (setf (variable-entry name environment)
                entry))
        (apply #'reinitialize-instance entry keyword-arguments))
    entry))

(defun variable-bound-p (variable-entry)
  (let ((cell (cell variable-entry)))
    (not (eq (car cell) +unbound+))))

;;; We need a class entry because this entry would be the unit of
;;; sharing of classes between environments.  For now, the entry acts
;;; as a simple indirection, but we may attach more information to it
;;; in the future.
(defclass class-entry ()
  ((%name :initarg :name :reader name)
   (%class :initform nil :initarg :class :accessor class)))

;;; Make sure NAME names a class entry in ENVIRONMENT.  If the :CLASS
;;; keyword argument is given, then the class of the entry (whether it
;;; exists or not) is set to the value of that argument.  If the
;;; :CLASS keyword argument is not given, and the entry exists, then
;;; the existing class of the entry is not modified.  If the :CLASS
;;; keyword argument is not given, and the entry does not exists, then
;;; the class of the entry is set to NIL, meaning there is no class
;;; with the name NAME in ENVIRONMENT.  The existing entry or the
;;; entry being created is returned.
(defun ensure-class-entry (name environment &key (class nil class-p))
  (let ((entry (gethash name (classes environment))))
    (if (null entry)
        (setf entry (make-instance 'class-entry :name name :class class)
              (gethash name (classes environment)) entry)
        (when class-p
          (setf (class entry) class)))
    entry))

;;; Functions.
(defmethod env:function-cell
    (client (environment run-time-environment) name)
  (cell (ensure-function-entry name environment)))

(defun %special-operator (environment name)
  (let ((entry (function-entry name environment)))
    (if (null entry)
        nil
        (special-operator entry))))

(defmethod env:special-operator
    (client (environment run-time-environment) name)
  (%special-operator environment name))

(defun (setf %special-operator) (new-value environment name)
  (let ((entry (if (null new-value)
                   (function-entry name environment)
                   (ensure-function-entry name environment))))
    (unless (null entry)
      (if (function-bound-p entry)
          (error 'env:attempt-to-define-special-operator-for-existing-function
                 :function-name name)
          (setf (special-operator entry) new-value))))
  new-value)

(defmethod (setf env:special-operator)
    (new-value client (environment run-time-environment) name)
  (setf (%special-operator environment name) new-value))

(defun %fdefinition (environment name)
  (let ((entry (function-entry name environment)))
    (cond ((null entry) nil)
          ((function-bound-p entry)
           (car (cell entry)))
          (t
           nil))))

(defmethod env:fdefinition
    (client (environment run-time-environment) name)
  (%fdefinition environment name))

(defun (setf %fdefinition) (new-value environment name)
  (let ((entry (if (null new-value)
                   (function-entry name environment)
                   (ensure-function-entry name environment))))
    (unless (null entry)
      (let ((cell (cell entry)))
        (setf (car cell)
              (if (null new-value)
                  (cdr cell)
                  new-value)))))
  new-value)

(defmethod (setf env:fdefinition)
    (new-value client (environment run-time-environment) name)
  (setf (%fdefinition environment name) new-value))

(defun %macro-function (environment name)
  (let ((entry (function-entry name environment)))
    (if (null entry)
        nil
        (macro-function entry))))

(defmethod env:macro-function
    (client (environment run-time-environment) name)
  (%macro-function environment name))

(defun (setf %macro-function) (new-value environment name)
  (let ((entry (if (null new-value)
                   (function-entry name environment)
                   (ensure-function-entry name environment))))
    (unless (null entry)
      ;; Check for error situations.  We consider it an error to call
      ;; this function, whether with NEW-VALUE being NIL or not, if
      ;; there is an existing definition of the name as a function.
      (when (function-bound-p entry)
        (error 'env:attempt-to-define-macro-for-existing-function
               :function-name name))
      (setf (macro-function entry) new-value)))
  new-value)

(defmethod (setf env:macro-function)
    (new-value client (environment run-time-environment) name)
  (setf (%macro-function environment name) new-value))

(defmethod env:compiler-macro-function
    (client (environment run-time-environment) name)
  (let ((entry (function-entry name environment)))
    (if (null entry)
        nil
        (compiler-macro-function entry))))

(defmethod (setf env:compiler-macro-function)
    (new-value client (environment run-time-environment) name)
  (let ((entry (if (null new-value)
                   (function-entry name environment)
                   (ensure-function-entry name environment))))
    (unless (null entry)
      (setf (compiler-macro-function entry) new-value)))
  new-value)

(defmethod env:function-type
    (client (environment run-time-environment) name)
  (let ((entry (function-entry name environment)))
    (if (null entry)
        nil
        (function-type entry))))

(defmethod (setf env:function-type)
    (new-value client (environment run-time-environment) name)
  (let ((entry (if (null new-value)
                   (function-entry name environment)
                   (ensure-function-entry name environment))))
    (unless (null entry)
      (cond ((not (null (special-operator entry)))
             (error 'env:attempt-to-set-function-type-of-special-operator
                    :function-name name))
            ((not (null (macro-function entry)))
             (error 'env:attempt-to-set-function-type-of-macro
                    :function-name name))
            (t
             (setf (function-type entry) new-value)))))
  new-value)

(defmethod env:function-inline
    (client (environment run-time-environment) name)
  (let ((entry (function-entry name environment)))
    (if (null entry)
        nil
        (function-inline entry))))

(defmethod (setf env:function-inline)
    (new-value client (environment run-time-environment) name)
  (let ((entry (if (null new-value)
                   (function-entry name environment)
                   (ensure-function-entry name environment))))
    (unless (null entry)
      (setf (function-inline entry) new-value))
    new-value))

(defmethod env:function-description
    (client (environment run-time-environment) name)
  nil)

(defmethod env:setf-expander
    (client (environment run-time-environment) symbol)
  (let ((entry (function-entry symbol environment)))
    (if (null entry)
        nil
        (setf-expander entry))))

(defmethod (setf env:setf-expander)
    (new-value client (environment run-time-environment) name)
  (let ((entry (if (null new-value)
                   (function-entry name environment)
                   (ensure-function-entry name environment))))
    (unless (null entry)
      (setf (setf-expander entry) new-value))
    new-value))

;;; Variables.
(defmethod env:variable-cell
    (client (environment run-time-environment) symbol)
  (cell (ensure-variable-entry symbol environment)))

(defmethod env:constant-variable
    (client (environment run-time-environment) symbol)
  (let ((entry (variable-entry symbol environment)))
    (if (or (null entry) (not (constant-variable-p entry)))
        (values nil nil)
        (values (constant-variable-p entry) (car (cell entry))))))

(defmethod (setf env:constant-variable)
    (new-value client (environment run-time-environment) symbol)
  (let* ((entry (ensure-variable-entry symbol environment))
         (cell (cell entry)))
    (if (constant-variable-p entry)
        (let ((value (car cell)))
          (if (not (eql value new-value))
              (error 'env:attempt-to-define-constant-for-existing-constant
                     :name symbol)
              value))
        (cond
          ((special-variable-p entry)
           (error 'env:attempt-to-define-constant-for-existing-special-variable
                  :name symbol))
          ((symbol-macro-p entry)
           (error 'env:attempt-to-define-constant-for-existing-symbol-macro
                  :name symbol))
          (t
           (setf (constant-variable-p entry) t)
           (setf (car cell) new-value))))))

(defmethod env:special-variable
    (client (environment run-time-environment) symbol)
  (let ((entry (variable-entry symbol environment)))
    (and (not (null entry))
         (special-variable-p entry))))

(defmethod (setf env:special-variable)
    (new-value client (environment run-time-environment) symbol init-p)
  (let ((entry (ensure-variable-entry symbol environment)))
    (cond ((constant-variable-p entry)
           (error 'env:attempt-to-define-special-variable-for-existing-constant
                  :name symbol))
          ((symbol-macro-p entry)
           (error 'env:attempt-to-define-special-variable-for-existing-symbol-macro
                  :name symbol))
          (t
           (setf (special-variable-p entry) t)
           (when init-p
             (setf (car (cell entry)) new-value))))))

(defmethod env:variable-value
    (client (environment run-time-environment) name)
  (let ((entry (variable-entry name environment)))
    (if (or (null entry)
            (eq (car (cell entry)) (cdr (cell entry))))
        (values nil nil)
        (values t (car (cell entry))))))

(defmethod env:symbol-macro
    (client (environment run-time-environment) symbol)
  (let ((entry (variable-entry symbol environment)))
    (if (or (null entry) (not (symbol-macro-p entry)))
        (values nil nil)
        (let ((expander (car (cell entry))))
          (values expander (funcall expander symbol environment))))))

(defmethod (setf env:symbol-macro)
    (new-value client (environment run-time-environment) symbol)
  (let ((entry (ensure-variable-entry symbol environment)))
    (cond
      ((constant-variable-p entry)
       (error 'env:attempt-to-define-symbol-macro-for-existing-constant
              :name symbol))
      ((special-variable-p entry)
       (error 'env:attempt-to-define-symbol-macro-for-existing-special-variable
              :name symbol))
      (t
       (setf (symbol-macro-p entry) t)
       (setf (car (cell entry)) (constantly new-value))))))

(defmethod env:variable-type
    (client (environment run-time-environment) symbol)
  (let ((entry (variable-entry symbol environment)))
    (cond ((null entry)
           t)
          ((constant-variable-p entry)
           (type-of (car (cell entry))))
          (t
           (let ((type (variable-type entry)))
             (if (null type) t type))))))

(defmethod (setf env:variable-type)
    (new-value client (environment run-time-environment) symbol)
  (let ((entry (ensure-variable-entry symbol environment)))
    (if (constant-variable-p entry)
        (error 'env:attempt-to-proclaim-the-type-of-a-constant-variable
               :name symbol)
        (setf (variable-type entry) new-value))))

(defmethod env:variable-description
    (client (environment run-time-environment) symbol)
  nil)

(defmethod env:type-expander
    (client (environment run-time-environment) symbol)
  (let ((entry (variable-entry symbol environment)))
    (if (null entry)
        nil
        (type-expander entry))))

(defmethod (setf env:type-expander)
    (new-value client (environment run-time-environment) symbol)
  (let ((entry (ensure-variable-entry symbol environment)))
    (setf (type-expander entry) new-value)))


;;; Other.

(defmethod env:find-class
    (client (environment run-time-environment) symbol)
  (let ((entry (gethash symbol (classes environment))))
    (values (if (null entry)
                nil
                (class entry)))))

(defmacro update-class-information
    ((name-var environment-var new-value-var) &body arguments)
  (let ((entry-var (gensym)))
    `(let ((,entry-var (gethash ,name-var (classes ,environment-var))))
       (if (null ,entry-var)
           (unless (null ,new-value-var)
             (ensure-class-entry ,name-var ,environment-var ,@arguments))
           (reinitialize-instance ,entry-var ,@arguments))
       ,new-value-var)))

(defmethod (setf env:find-class)
    (new-value client (environment run-time-environment) symbol)
  (update-class-information (symbol environment new-value)
    :class new-value))

(defmethod env:class-description
    (client (environment run-time-environment) symbol)
  nil)

(defmethod env:find-package
    (client (environment run-time-environment) name)
  (values (gethash name (packages environment))))

(defmethod (setf env:find-package)
    (new-package client (environment run-time-environment) name)
  (if (null new-package)
      (remhash name (packages environment))
      (setf (gethash name (packages environment)) new-package)))


;;; Declarations.

(defmethod env:proclamation
    (client (environment run-time-environment) name)
  (values (gethash name (declarations environment))))

(defmethod (setf env:proclamation)
    (new-value client (environment run-time-environment) name)
  (cond ((null new-value)
         (remhash name (declarations environment)))
        (t
         (setf (gethash name (declarations environment)) new-value))))

(defmethod env:map-defined-functions
    (client (environment run-time-environment) function)
  (maphash (lambda (name function-entry)
             (when (function-bound-p function-entry)
               (funcall function name (car (cell function-entry)))))
           (functions environment)))

(defmethod env:map-defined-classes
    (client (environment run-time-environment) function)
  (maphash (lambda (name entry)
             (let ((class (class entry)))
               (unless (null class)
                 (funcall function name class))))
           (classes environment)))

(defmethod env:import-function
    (client
     (from-environment run-time-environment)
     name
     (to-environment run-time-environment))
  (let ((entry (ensure-function-entry name from-environment)))
    (setf (gethash name (functions to-environment))
          entry)))
