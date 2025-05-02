import dash
from dash import dcc, html
from dash.dependencies import Input, Output
from pymongo import MongoClient
import plotly.express as px
import pandas as pd 
from flask_jwt_extended import JWTManager, create_access_token, jwt_required, get_jwt_identity
import base64
import json
import os

# Configuración de la aplicación Dash
app = dash.Dash(__name__)
app.server.config['JWT_SECRET_KEY'] = 'claveSuperSecreta123'  # Clave secreta para JWT
jwt = JWTManager(app.server)

# Variables globales
mongo_url = None
mongo_client = None
user_authenticated = False

# Función para conectar a MongoDB
def generate_mongo_url(user, password):
    return f"mongodb+srv://{user}:{password}@cluster0.1ti18.mongodb.net/test?retryWrites=true&w=majority"

# Función para obtener las bases de datos de MongoDB
def get_databases():
    try:
        dbs = mongo_client.list_database_names()
        return dbs
    except Exception as e:
        print(f"Error al obtener bases de datos: {e}")
        return []

# Función para obtener las colecciones de una base de datos
def get_collections(db_name):
    try:
        db = mongo_client[db_name]
        collections = db.list_collection_names()
        return collections
    except Exception as e:
        print(f"Error al obtener colecciones: {e}")
        return []

# Función para obtener las columnas de una colección
def get_columns(db_name, collection_name):
    try:
        db = mongo_client[db_name]
        collection = db[collection_name]
        sample_data = collection.find().limit(5)
        return sample_data[0].keys() if sample_data.count() > 0 else []
    except Exception as e:
        print(f"Error al obtener columnas: {e}")
        return []

# Configuración de la UI
app.layout = html.Div([
    html.Div([
        html.H1("Login y Visualización de Datos"),
        html.Div([
            dcc.Input(id='username', type='text', placeholder='Usuario'),
            dcc.Input(id='password', type='password', placeholder='Contraseña'),
            html.Button('Iniciar Sesión', id='login', n_clicks=0),
        ]),
        html.Div(id='login-status', children=''),
    ], id='login-container'),

    html.Div([
        dcc.Dropdown(id='database-dropdown', placeholder="Selecciona Base de Datos"),
        dcc.Dropdown(id='collection-dropdown', placeholder="Selecciona Colección"),
        dcc.Dropdown(id='xvar-dropdown', placeholder="Selecciona Variable X"),
        dcc.Dropdown(id='yvar-dropdown', placeholder="Selecciona Variable Y"),
        dcc.Dropdown(id='chart-type-dropdown', options=[
            {'label': 'Barras', 'value': 'bar'},
            {'label': 'Puntos', 'value': 'scatter'},
            {'label': 'Líneas', 'value': 'line'},
            {'label': 'Histograma', 'value': 'histogram'},
            {'label': 'Caja', 'value': 'box'}
        ], placeholder="Selecciona Tipo de Gráfico"),
        html.Button('Generar Gráfico', id='generate-graph', n_clicks=0),
        dcc.Graph(id='graph-output'),
    ], id='app-content', style={'display': 'none'}),

    html.Button('Cerrar Sesión', id='logout', n_clicks=0)
])

# Función de login
@app.callback(
    Output('login-status', 'children'),
    Output('app-content', 'style'),
    Input('login', 'n_clicks'),
    state=[Input('username', 'value'), Input('password', 'value')]
)
def login(n_clicks, username, password):
    global user_authenticated, mongo_url, mongo_client
    if n_clicks > 0 and username and password:
        mongo_url = generate_mongo_url(username, password)
        try:
            mongo_client = MongoClient(mongo_url)
            mongo_client.server_info()  # Verifica la conexión
            user_authenticated = True

            # Generar token
            token = create_access_token(identity=username)
            return f'Bienvenido, {username}.', {'display': 'block'}
        except Exception as e:
            return f'Error de autenticación: {str(e)}', {'display': 'none'}
    return '', {'display': 'none'}

# Cargar las bases de datos después del login
@app.callback(
    Output('database-dropdown', 'options'),
    Input('login', 'n_clicks')
)
def load_databases(n_clicks):
    if user_authenticated and mongo_client:
        dbs = get_databases()
        return [{'label': db, 'value': db} for db in dbs]
    return []

# Cargar colecciones basadas en la base de datos seleccionada
@app.callback(
    Output('collection-dropdown', 'options'),
    Input('database-dropdown', 'value')
)
def load_collections(db_name):
    if db_name:
        collections = get_collections(db_name)
        return [{'label': col, 'value': col} for col in collections]
    return []

# Cargar columnas basadas en la colección seleccionada
@app.callback(
    Output('xvar-dropdown', 'options'),
    Output('yvar-dropdown', 'options'),
    Input('database-dropdown', 'value'),
    Input('collection-dropdown', 'value')
)
def load_columns(db_name, collection_name):
    if db_name and collection_name:
        columns = get_columns(db_name, collection_name)
        options = [{'label': col, 'value': col} for col in columns]
        return options, options
    return [], []

# Generar el gráfico
@app.callback(
    Output('graph-output', 'figure'),
    Input('generate-graph', 'n_clicks'),
    state=[Input('database-dropdown', 'value'), Input('collection-dropdown', 'value'),
           Input('xvar-dropdown', 'value'), Input('yvar-dropdown', 'value'),
           Input('chart-type-dropdown', 'value')]
)
def generate_graph(n_clicks, db_name, collection_name, xvar, yvar, chart_type):
    if n_clicks > 0 and db_name and collection_name and xvar and yvar:
        db = mongo_client[db_name]
        collection = db[collection_name]
        data = pd.DataFrame(list(collection.find()))
        fig = None

        if chart_type == 'bar':
            fig = px.bar(data, x=xvar, y=yvar)
        elif chart_type == 'scatter':
            fig = px.scatter(data, x=xvar, y=yvar)
        elif chart_type == 'line':
            fig = px.line(data, x=xvar, y=yvar)
        elif chart_type == 'histogram':
            fig = px.histogram(data, x=xvar)
        elif chart_type == 'box':
            fig = px.box(data, y=yvar)

        return fig
    return {}

# Función para logout
@app.callback(
    Output('login-container', 'style'),
    Input('logout', 'n_clicks')
)
def logout(n_clicks):
    global user_authenticated
    if n_clicks > 0:
        user_authenticated = False
        return {'display': 'block'}
    return {}

if __name__ == '__main__':
    app.run_server(debug=True)
