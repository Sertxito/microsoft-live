ARG SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:10.0.401@sha256:e70cdb7f80b0348f5cb85f19a8f670fca061f033d57eed12fa003d58b0e06317
ARG RUNTIME_IMAGE=mcr.microsoft.com/dotnet/aspnet:10.0.14@sha256:1a48394b6f29d3a32c79d9edecd4abda0ecbe8776d567dbfc4590ed6979c740c
FROM ${SDK_IMAGE} AS build
WORKDIR /source
COPY global.json Directory.Build.props ./
COPY src/ src/
COPY knowledge/tutorials/ knowledge/tutorials/
RUN dotnet restore src/Harness.Api/Harness.Api.csproj
RUN dotnet publish src/Harness.Api/Harness.Api.csproj -c Release --no-restore -o /app /p:UseAppHost=false

FROM ${RUNTIME_IMAGE} AS runtime
WORKDIR /app
COPY --from=build /app .
USER $APP_UID
EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080
ENTRYPOINT ["dotnet", "Harness.Api.dll"]
