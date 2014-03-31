#|
  This file is a part of Verbose
  (c) 2013 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
  Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package :verbose)

(defvar *global-controller* NIL)
(defvar *shared-instances* (make-hash-table))

(setf (gethash 'standard-output *shared-instances*) *standard-output*)
(setf (gethash 'error-output *shared-instances*) *error-output*)

(defclass controller (pipeline)
  ((thread :accessor controller-thread)
   (message-condition :initform (make-condition-variable :name "MESSAGE-CONDITION") :reader message-condition)
   (message-pipe :initform (make-array '(10) :adjustable T :fill-pointer 0) :accessor message-pipe)
   (message-lock :initform (make-lock "MESSAGE-LOCK") :reader message-lock))
  (:documentation "Main controller class that holds the logging construct."))

(defmethod initialize-instance :after ((controller controller) &rest rest)
  (declare (ignore rest))
  (setf (controller-thread controller)
        (make-thread #'controller-loop
                     :name "CONTROLLER MESSAGE LOOP"
                     :initial-bindings `((*shared-instances* . ,*shared-instances*)
                                         (*global-controller* . ,controller)))))

(defun controller-loop ()
  (let* ((controller *global-controller*)
         (lock (message-lock controller))
         (condition (message-condition controller))
         (pipeline (pipeline controller)))
    (acquire-lock lock)
    (loop do
      (with-simple-restart (skip "Skip processing the message.")
        (let ((queue (message-pipe controller))
              (*standard-output* (gethash 'standard-output *shared-instances*))
              (*error-output* (gethash 'error-output *shared-instances*)))
          (setf (message-pipe controller) (make-array '(10) :adjustable T :fill-pointer 0))
          (release-lock lock)
          (loop for message across queue
                do (pass pipeline message))))
      (acquire-lock lock)
      (condition-wait condition lock))))

(defmethod pass ((controller controller) message)
  (with-lock-held ((message-lock controller))
    (vector-push-extend message (message-pipe controller)))
  (condition-notify (message-condition controller))
  NIL)

(defun shared-instance (key)
  (with-lock-held ((message-lock *global-controller*))
    (gethash key *shared-instances*)))

(defgeneric (setf shared-instance) (val key)
  (:method (val key)
    (setf (gethash key *shared-instances*) val)))
