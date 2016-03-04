package main

import (
    "strconv"
    "fmt"
    "net/http"
    "html"
    "html/template"
    "strings"
    "log"
    "database/sql"
    _ "github.com/lib/pq"
    //_ "github.com/lxn/go-pgsql"
)

var answers = []string{ "stem niet", "stem voor", "stem tegen", "stem blanco" }
var stdHeader = "Wat vindt u van de volgende stelling"
var startHeader = `Welkom bij de kieswijzer voor het referendum van 6 april.
In tegenstelling tot de meeste andere kieswijzers zijn de stellingen hier door
andere gebruikers ingebracht en uw keuzes beinvloeden de volgende stellingen 
die u te zien krijgt. Wij zouden het ook erg leuk vinden als u een stelling
verzint als de uitkomst iets anders is als u zelf had verwacht. Stellingen waar
veel mensen geen mening over hebben, hebben minder kans om geselecteerd te worden. Wat vindt u van de eerste stelling:`

var questionPage = `{{.Header}}
<table border="1">
<tr><td colspan="3">{{.Question}}</td></tr>
<tr>
	<td><a href="/yes/{{.Id}}">eens</a></td>
	<td><a href="/no/{{.Id}}">oneens</a></td>
	<td><a href="/dontcare/{{.Id}}">maakt niet uit/stomme vraag</a></td>
</tr>
</table>`


var pleaseNewQuestion = `De andere mensen die het met u eens waren over de gevraagde stellingen hadden de andere keuze gemaakt. Kunt u een stelling toevoegen die hen
zal overtuigen "{{.AnswerText}}" te kiezen.
<form action="/addQuestion/{{.AnswerNum}}/{{.Id}}" method="POST">
   <div>
     <textarea name="body" rows="5" cols="80"> 
     </textarea>
   </div>
   <div>
     <input type="submit" value="Save">
   </div>
</form>`


type Question struct {
     Header string
     Question string
     Id string
}

type NewQuestion struct {
    AnswerText string
    AnswerNum string
    Id string
}

func questionOut( w http.ResponseWriter, h string, q string, id string ) {
    t,err := template.New("Question page").Parse(questionPage)
    checkErr(err);
    d:=Question{ Header: h, Question: q, Id: id }
    err = t.Execute( w, d )
    checkErr(err);
}

func selectQuestion( w http.ResponseWriter, db *sql.DB, id string, criteria string, qHeader string ) {
    stmnt, err := db.Prepare("select id, text from question_select where choice_node = $1 and " + criteria + " order by sorter desc;" )
    checkErr(err)

    rows,err := stmnt.Query(id)
    defer rows.Close()
    checkErr(err)

    if rows.Next() {
        var qid string
	var qtext string
	err := rows.Scan( &qid, &qtext )
	checkErr(err)
	db.Exec("COMMIT");
	questionOut( w, qHeader, qtext, qid )
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
	    fmt.Fprintf(w, "<body><table>")
	    fmt.Fprintf(w, "<tr><th>Wij geven het advies voor het referendum van 6 april: %s</th></tr>", atext )
	    fmt.Fprintf(w, "<tr><td><a href=\"/start\">Fantastisch, ik wil nog eens</a></td></tr>");
	    for i, text := range answers {
	    	if text != atext {
		    fmt.Fprintf(w,"<tr><td><a href=\"/newQuestion/%d/%d\">Ik vind \"%s\" beter</a></td></tr>", i, aid, text )
		}
            }

            fmt.Fprintf(w, "</table></body>")
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
	selectQuestion( w, db, next_id, "1 = 1", stdHeader )
    } else {
	fmt.Fprintf(w, "Ongeldige waarde")
	fmt.Fprintf(w, "</body>" )
    }
}

func start( w http.ResponseWriter ) {

    db, err := sql.Open("postgres", "dbname=kiesWijzer")
    defer db.Close()
    checkErr(err)

    selectQuestion( w, db, "1", "1=1", startHeader )
}    

func newQuestion( w http.ResponseWriter, answer int, id string ) {
    t,err := template.New("Question page").Parse(pleaseNewQuestion)
    checkErr(err);
    d:=NewQuestion{ AnswerText: answers[answer], AnswerNum: strconv.Itoa(answer), Id: id }
    err = t.Execute( w, d )
    checkErr(err);
}

func addQuestion( w http.ResponseWriter, answer int, id string, tekst string ) {
    db, err := sql.Open("postgres", "dbname=kiesWijzer")
    defer db.Close()
    checkErr(err)

    stmnt, err := db.Prepare("select add_question( $1, $2, $3 );")
    checkErr(err)
    stmnt.Query(id, answers[answer], tekst )
    checkErr(err)
    fmt.Fprintf(w, "Dank u.<a href=\"/start\">nog eens</a></body>" )

    db.Exec("commit")
}

func dontcare( w http.ResponseWriter, id string ) {
    db, err := sql.Open("postgres", "dbname=kiesWijzer")
    defer db.Close()
    checkErr(err)
    
    stmnt, err := db.Prepare( "update question set ( count_total ) = ( count_total +1) where id = $1" )
    checkErr(err)
    _, err = stmnt.Exec(id)
    checkErr(err)

    stmnt, err = db.Prepare("select choice_node, sorter from question_select where id = $1;")
    checkErr(err)
    rows, err := stmnt.Query( id )
    defer rows.Close()

    if rows.Next() {
    	var next_id string
	var sorter string
	rows.Scan( &next_id, &sorter )
	selectQuestion( w, db, next_id, "sorter < '" + sorter + "'", stdHeader )
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
	addQuestion( w, i, s[3], html.EscapeString( r.FormValue("body") ) )
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
