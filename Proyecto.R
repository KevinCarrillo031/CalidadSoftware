#prueba de escaneo


library(shiny)
library(mongolite)
library(dplyr)
library(plotly)
library(ggplot2)
library(DT)
library(DBI)
library(jsonlite)
library(shinyjs)
library(shinyalert)
library(jose)
library(base64enc)
library(shiny.router)

# Función para generar la URL de conexión a MongoDB
generate_mongo_url <- function(user, password) {
  sprintf("mongodb+srv://%s:%s@cluster0.1ti18.mongodb.net/test?retryWrites=true&w=majority", 
          user, password)
}

# Llave secreta para firmar el token (NO LA EXPONGAS pÃºblicamente)
jwt_secret <- "claveSuperSecreta123"

# Crear token
crear_token <- function(username) {
  claims <- jwt_claim(user = username, exp = as.numeric(Sys.time()) + 3600)
  jwt_encode_hmac(claims, secret = jwt_secret)
}

# Verificar token
verificar_token <- function(token) {
  tryCatch({
    jwt_decode_hmac(token, secret = jwt_secret)
  }, error = function(e) {
    print(paste("Error al decodificar:", e$message))
    NULL
  })
}

# Función para obtener bases de datos
get_databases <- function(url_mongo) {
  tryCatch({
    conexion <- mongo(collection = "$cmd", db = "admin", url = url_mongo)
    resultado <- conexion$run('{"listDatabases": 1}')
    if (!is.null(resultado$databases)) {
      return(resultado$databases$name)
    } else {
      return(NULL)
    }
  }, error = function(e) {
    return(NULL)
  })
}

# Función para obtener colecciones
get_collections <- function(db_name, url_mongo) {
  tryCatch({
    conexion <- mongo(db = db_name, url = url_mongo)
    conexion$run('{ "listCollections": 1 }')$cursor$firstBatch$name
  }, error = function(e) {
    return(NULL)
  })
}

# Función para obtener columnas de una colección
get_columns <- function(db_name, collection_name, url_mongo) {
  conexion <- mongo(collection = collection_name, db = db_name, url = url_mongo)
  if (!conexion$count()) return(NULL)
  datos <- conexion$find('{}', limit = 5)
  colnames(datos)
}

ui <- fluidPage(
  useShinyjs(),  # Necesario para shinyjs
  useShinyalert(),
  
  titlePanel("Login y Visualización de Datos"),
  
  tags$head(
    # Script para manejar el JWT
    tags$script(HTML("
      document.addEventListener('DOMContentLoaded', function() {
        // Recuperar el token desde sessionStorage
        let jwt = sessionStorage.getItem('jwt');
        
        // Si no estÃ¡ en sessionStorage, revisar cookies
        if (!jwt) {
          let match = document.cookie.match(/(^| )jwt=([^;]+)/);
          if (match) {
            jwt = match[2];
          }
        }

        // Enviar a Shiny si existe
        if (jwt) {
          setTimeout(function() {
            Shiny.setInputValue('jwt_token', jwt, {priority: 'event'});
          }, 300);
        }
      });
    ")),
    
    # Estilos CSS para el login
    tags$style(HTML("
      .login-container { 
        display: flex; 
        justify-content: center; 
        align-items: center; 
        height: 100vh; 
      }
      .login-box { 
        width: 300px; 
        padding: 20px; 
        border: 1px solid #ccc; 
        border-radius: 10px; 
        background: white; 
        box-shadow: 0px 4px 6px rgba(0, 0, 0, 0.1); 
        text-align: center; 
        position: fixed; 
        top: 50%; 
        left: 50%; 
        transform: translate(-50%, -50%);
        z-index: 999;
      }
    "))
  ),
  
  # Login Panel
  div(id = "loginPanel", class = "login-container",
      div(class = "login-box",
          textInput("username", "Usuario"),
          passwordInput("password", "Contraseña"),
          actionButton("login", "Iniciar Sesión")
      )
  ),
  
  # Contenido de la app (oculto inicialmente)
  shinyjs::hidden(
    div(id = "app_content",
        sidebarLayout(
          sidebarPanel(
            selectInput("bd", "Base de Datos", choices = NULL),
            selectInput("coleccion", "Colección", choices = NULL),
            selectInput("xvar", "Variable X", choices = NULL),
            selectInput("yvar", "Variable Y", choices = NULL),
            selectInput("grafico", "Tipo de grÃ¡fico", choices = c("Barras", "Puntos", "LÃ­neas", "Histograma", "Caja")),
            actionButton("generar", "Generar Gráfico"),
            actionButton("logout", "Cerrar Sesión")
          ),
          mainPanel(
            plotlyOutput("graficoSalida"),
            DTOutput("tablaDatos")
          )
        )
    )
  )
)


server <- function(input, output, session) {
  user_authenticated <- reactiveVal(FALSE)
  mongo_url <- reactiveVal(NULL)
  
  # Funciones para crear y verificar el JWT
  crear_token <- function(username) {
    claims <- jwt_claim(user = username, exp = as.numeric(Sys.time()) + 3600)
    jwt_encode_hmac(claims, secret = jwt_secret)
  }
  
  verificar_token <- function(token) {
    tryCatch({
      decoded <- jwt_decode_hmac(token, secret = jwt_secret)
      return(decoded$payload$user)
    }, error = function(e) {
      return(NULL)
    })
  }
  
  observeEvent(input$login, {
    req(input$username, input$password)
    url <- generate_mongo_url(input$username, input$password)
    conexion <- tryCatch({
      mongo(collection = "test", url = url)
    }, error = function(e) {
      return(NULL)
    })
    
    if (!is.null(conexion) && conexion$count('{}') >= 0) {
      mongo_url(url)
      user_authenticated(TRUE)
      updateSelectInput(session, "bd", choices = get_databases(url))
      hide("loginPanel")
      show("app_content")
      
      # Generar token y guardarlo en cookie y sessionStorage
      token <- crear_token(input$username)
      runjs(sprintf("document.cookie = 'token=%s; path=/; secure; samesite=strict;';", token))
      runjs(sprintf("sessionStorage.setItem('jwt', '%s');", token))
    } else {
      showNotification("Error de autenticación", type = "error")
      user_authenticated(FALSE)
    }
  })
  
  observe({
    if (user_authenticated()) {
      hide("loginPanel")
      show("app_content")
    } else {
      show("loginPanel")
      hide("app_content")
    }
  })
  
  observeEvent(input$bd, {
    req(input$bd, mongo_url())
    updateSelectInput(session, "coleccion", choices = get_collections(input$bd, mongo_url()))
  })
  
  observeEvent(input$coleccion, {
    req(input$coleccion, mongo_url())
    cols <- get_columns(input$bd, input$coleccion, mongo_url())
    updateSelectInput(session, "xvar", choices = cols)
    updateSelectInput(session, "yvar", choices = cols)
  })
  
  datos_reactivos <- reactiveVal()
  
  observeEvent(input$generar, {
    req(input$coleccion, input$xvar, input$yvar, mongo_url())
    conexion <- mongo(collection = input$coleccion, db = input$bd, url = mongo_url())
    datos <- conexion$find('{}')
    datos_reactivos(datos)
    
    p <- plot_ly(datos, x = ~.data[[input$xvar]])
    if (input$grafico == "Barras") p <- p %>% add_bars(y = ~.data[[input$yvar]])
    else if (input$grafico == "Puntos") p <- p %>% add_markers(y = ~.data[[input$yvar]])
    else if (input$grafico == "LÃ­neas") p <- p %>% add_lines(y = ~.data[[input$yvar]])
    else if (input$grafico == "Histograma") p <- p %>% add_histogram()
    else if (input$grafico == "Caja") p <- p %>% add_boxplot(y = ~.data[[input$yvar]])
    
    output$graficoSalida <- renderPlotly({ p })
  })
  
  observeEvent(input$logout, {
    shinyalert(
      title = "Â¿Cerrar sesión?",
      text = "Â¿EstÃ¡s seguro de que deseas cerrar la sesión?",
      type = "warning",
      showCancelButton = TRUE,
      confirmButtonText = "SÃ­",
      cancelButtonText = "No",
      callbackR = function(confirm) {
        if (confirm) {
          runjs("document.cookie = 'jwt=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';")
          runjs("sessionStorage.removeItem('jwt');")
          user_authenticated(FALSE)
          mongo_url(NULL)
          show("loginPanel")
          hide("app_content")
        }
      }
    )
  })
  
  observeEvent(input$jwt_token, {
    token <- input$jwt_token
    print(paste("Token recibido:", token))
    
    payload <- tryCatch({
      jwt_decode_hmac(token, secret)
    }, error = function(e) {
      print(paste("Error al decodificar:", e$message))
      NULL
    })
    
    if (!is.null(payload)) {
      print("Token vÃ¡lido, restaurando sesión")
      shinyjs::hide("loginPanel")
      shinyjs::show("app_content")
    } else {
      print("Token invÃ¡lido, se muestra loginPanel.")
      shinyjs::show("loginPanel")
      shinyjs::hide("app_content")
    }
  })
  
  
  # Renderizar la tabla de datos
  output$tablaDatos <- renderDT({
    req(datos_reactivos())
    datatable(datos_reactivos(), selection = "single")
  })
}

shinyApp(ui, server)
