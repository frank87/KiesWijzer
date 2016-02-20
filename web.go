package main

import (
    "strconv"
    "fmt"
    "net/http"
    "strings"
    "log"
    "database/sql"
    _ "github.com/lib/pq"
    //_ "github.com/lxn/go-pgsql"
)

var answers = []string{ "stem niet", "stem voor", "stem tegen" }

func selectQuestion( w http.ResponseWriter, db *sql.DB, id string, criteria string ) {
    stmnt, err := db.Prepare("select id, text from question_select where choice_node = $1 and " + criteria + " order by sorter desc;" )
    checkErr(err)

    rows,err := stmnt.Query(id)
    defer rows.Close()
    checkErr(err)

    if rows.Next() {
        var qid int
	var qtext string
	err := rows.Scan( &qid, &qtext )
	checkErr(err)
	fmt.Fprintf(w, "%s <a href=\"/yes/%d\">EENS</a> <a href=\"/no/%d\">ONEENS</a> <a href=\"/dontcare/%d\">slechte stelling/maakt niet uit</a>", qtext, qid, qid, qid )
	db.Exec("COMMIT");
	fmt.Fprintf(w, "</body>")
    } else {
    	stmnt, err := db.Prepare("select id, answer_text from choice_node where id = $1;" )
        checkErr(err)
	rows, err := stmnt.Query(id)
	defer rows.Close()
	checkErr(err);
	if rows.Next() { 
	    var aid int 
	    var atext string
	    rows.Scan( &aid, &atext )
	    fmt.Fprintf(w, "Wij geven het advies voor het referendum van 6 april: %s</br>", atext )
	    fmt.Fprintf(w, "<a href=\"/start\">Fantastisch, ik wil nog eens</a><br>");
	    for i, text := range answers {
	    	if text != atext {
		    fmt.Fprintf(w,"<a href=\"/newQuestion/%d/%d\">Ik vind \"%s\" beter</a></br>", i, aid, text )
		}
            }

            fmt.Fprintf(w, "</body>")
	} else {
	    fmt.Fprintf(w, "Daar is iets fout</body>");
	}
    }
} 


func yesno( w http.ResponseWriter, t string, id string ) {

    db, err := sql.Open("postgres", "dbname=kiesWijzer")
    defer db.Close()
    checkErr(err)
    defer db.Close()

    fmt.Println( "select on_" + t + " from question where id = $1" )
    stmnt, err := db.Prepare( "select on_" + t + " from question where id = $1" )
    checkErr(err)
    rows, err := stmnt.Query( id )
    defer rows.Close()
    checkErr(err)
    if rows.Next() {
	var next_id string
	rows.Scan(&next_id)
	stmnt, err = db.Prepare( "update question set ( count_"+t+", count_total) = ( count_"+t+" + 1, count_total +1) where id = $1" )
	_, err = stmnt.Exec(id)
	checkErr(err)
	selectQuestion( w, db, next_id, "1 = 1" )
    } else {
	fmt.Fprintf(w, "Ongeldige waarde")
	fmt.Fprintf(w, "</body>" )
    }
}

func start( w http.ResponseWriter ) {

    db, err := sql.Open("postgres", "dbname=kiesWijzer")
    defer db.Close()
    checkErr(err)

    fmt.Fprintf(w, "<body>Welkom bij deze kieswijzer. Op grond van de overeenkomsten tussen uw antwoorden en die van eerdere gebruikers geven wij een advies voor het referendum op 6 april<br>De eerste stelling:<br>" )

    selectQuestion( w, db, "1", "1=1" )
}    

func newQuestion( w http.ResponseWriter, answer int, id string ) {
    fmt.Fprintf(w, "Geef een stelling die anderen zal overtuigen om ook \"%s\" te kiezen<br>", answers[answer] )
    fmt.Fprintf(w, "<form action=\"/addQuestion/%d/%s\" method=\"POST\"><div><textarea name=\"body\" rows=\"5\" cols=\"80\">x</textarea></div><div><input type=\"submit\" value=\"Save\"></div></form>", answer, id);
    fmt.Fprintf(w, "</body>")
}

func addQuestion( w http.ResponseWriter, anser int, id string, tekst string ) {
    db, err := sql.Open("postgres", "dbname=kiesWijzer")
    defer db.Close()
    checkErr(err)

    stmnt, err := db.Prepare("select add_question( $1, $2, $3 );")
    checkErr(err)
    stmnt.Query(id, answers[anser], tekst )
    checkErr(err)
    fmt.Fprintf(w, "Dank u.<a href=\"/start\">nog eens</a></body>" )

    db.Exec("commit")
}

func dontcare( w http.ResponseWriter, id string ) {
    db, err := sql.Open("postgres", "dbname=kiesWijzer")
    defer db.Close()
    checkErr(err)
    
    stmnt, err := db.Prepare("select choice_node, sorter from question_select where id = $1;")
    checkErr(err)
    rows, err := stmnt.Query( id )
    defer rows.Close()

    stmnt, err = db.Prepare( "update question set ( count_total ) = ( count_total +1) where id = $1" )
    _, err = stmnt.Exec(id)
    checkErr(err)
    if rows.Next() {
    	var next_id string
	var sorter string
	rows.Scan( &next_id, &sorter )
	selectQuestion( w, db, next_id, "sorter < '" + sorter + "'" )
    } else {
    	fmt.Fprintf(w, "Duuhhh</body>" )
    }


}
    

func response(w http.ResponseWriter, r *http.Request) {
    r.ParseForm()  // parse arguments, you have to call this by yourself

    s := strings.Split(r.URL.Path, "/")
    fmt.Println(r.URL);
    fmt.Println(r.FormValue("body"))

    fmt.Fprintf(w, "<body>")
    if s[1] == "no" {
	yesno( w, "no", s[2] )
    } else if s[1] == "yes" {
	yesno( w, "yes", s[2] )
    } else if s[1] == "dontcare" {
	dontcare( w, s[2] )
    } else if s[1] == "newQuestion" {
	i, _ := strconv.Atoi(s[2])
	newQuestion( w, i, s[3] )
    } else if s[1] == "addQuestion" {
	i, _ := strconv.Atoi(s[2])
	addQuestion( w, i, s[3], r.FormValue("body") )
    } else {
    	start(w)
    }
}

func checkErr(err error) {
    if err != nil {
        panic(err)
    }
}

func main() {
    http.HandleFunc("/", response ) // set router
    err := http.ListenAndServe(":9090", nil) // set listen port
    if err != nil {
        log.Fatal("ListenAndServe: ", err)
    }
}
