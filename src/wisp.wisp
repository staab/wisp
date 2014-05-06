(ns wisp.wisp
  "Wisp program that reads wisp code from stdin and prints
  compiled javascript code into stdout"
  (:require [fs :refer [createReadStream writeFileSync]]
            [path :refer [basename dirname join resolve]]
            [module :refer [Module]]
            [commander]

            [wisp.string :refer [split join upper-case replace]]
            [wisp.sequence :refer [first second last count reduce rest map
                                   conj partition assoc drop empty?]]

            [wisp.repl :refer [start] :rename {start start-repl}]
            [wisp.engine.node]
            [wisp.runtime :refer [str subs = nil?]]
            [wisp.ast :refer [pr-str name]]
            [wisp.compiler :refer [compile]]))

(defn compile-stdin
  [options]
  (with-stream-content process.stdin
                       compile-string
                       options))

(defn compile-file
  [path options]
  (map (fn [file] (with-stream-content
                       (createReadStream file)
                       compile-string
                       (conj {:source-uri file} options))) path))

(defn compile-string
  [source options]
  (let [channel (or (:print options) :code)
        output (compile source options)
        content (if (= channel :code)
                  (:code output)
                  (JSON.stringify (get output channel) 2 2))]
    (if (:ast options) (map (fn [item]
                              (.write process.stdout
                                      (str (pr-str item.form) "\n")))
                              output.ast))
    (if (and (:output options) (:source-uri options) content)
      (writeFileSync (path.join (:output options) ;; `join` relies on `path`
                           (str (basename (:source-uri options) ".wisp") ".js"))
                     content)
      (.write process.stdout (or content "nil")))
    (if (:error output) (throw (:error output)))))

(defn with-stream-content
  [input resume options]
  (let [content ""]
    (.setEncoding input "utf8")
    (.resume input)
    (.on input "data" #(set! content (str content %)))
    (.once input "end" (fn [] (resume content options)))))


(defn run
  [path]
  ;; Loading module as main one, same way as nodejs does it:
  ;; https://github.com/joyent/node/blob/master/lib/module.js#L489-493
  (Module._load (resolve (get path 0)) null true))

(defmacro ->
  [& operations]
  (reduce
   (fn [form operation]
     (cons (first operation)
           (cons form (rest operation))))
   (first operations)
   (rest operations)))

(defn main
  []
  (let [options commander]
    (-> options
      (.usage "[options] <file ...>")
      (.option "-r, --run"           "Compile and execute the file")
      (.option "-c, --compile"       "Compile to JavaScript and save as .js files")
      (.option "-i, --interactive"   "Run an interactive wisp REPL")
      (.option "--debug, --print <type>"    "Print debug information. Possible values are `form`, `ast` and `js-ast`")
      (.option "-o, --output <dir>"  "Output to specified directory")
      (.option "--no-map"            "Disable source map generation")
      (.parse process.argv))
    (set! (aget options "no-map") (not (aget options "map"))) ;; commander auto translates to camelCase
    (cond options.run (run options.args)
          (not process.stdin.isTTY) (compile-stdin options)
          options.interactive (start-repl)
          options.compile (compile-file options.args options)
          options.args (run options.args)
          :else (start-repl)
   )))
