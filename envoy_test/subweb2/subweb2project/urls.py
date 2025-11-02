from django.urls import path, include
urlpatterns = [
    path("subweb2/", include("subapp.urls")),
    path("health", lambda request: __import__("django.http").http.HttpResponse("ok")),
]
